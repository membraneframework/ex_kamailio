defmodule ExKamailio.WebSocketTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log

  alias ExKamailio.{SDP, WebSocket}

  defmodule TestHandler do
    use ExKamailio.CallHandler

    @local %ExKamailio.Endpoint{ip: "192.0.2.1", rtp_port: 30_000, rtcp_port: 30_001}

    @impl true
    def init(opts), do: {:ok, %{calls: opts[:report_to] || self()}}

    @impl true
    def handle_offer(offer, session, state) do
      send(state.calls, {:offer_called, session})
      {:ok, SDP.rewrite_endpoint(offer, @local), state}
    end

    @impl true
    def handle_answer(answer, session, state) do
      send(state.calls, {:answer_called, session})
      {:ok, SDP.rewrite_endpoint(answer, @local), state}
    end

    @impl true
    def handle_delete(session, state) do
      send(state.calls, {:delete_called, session})
      {:ok, state}
    end
  end

  @offer_sdp """
  v=0\r
  o=alice 1 1 IN IP4 192.168.1.10\r
  s=-\r
  c=IN IP4 192.168.1.10\r
  t=0 0\r
  m=audio 49170 RTP/AVP 0 101\r
  a=sendrecv\r
  """

  setup do
    Application.put_env(:ex_kamailio, :handler, TestHandler)
    Application.put_env(:ex_kamailio, :handler_opts, report_to: self())

    start_supervised!({Registry, keys: :unique, name: ExKamailio.CallRegistry})

    start_supervised!(
      {DynamicSupervisor, name: ExKamailio.CallSupervisor, strategy: :one_for_one}
    )

    {:ok, state} = WebSocket.init([])
    {:ok, state: state}
  end

  defp registered?(call_id), do: Registry.lookup(ExKamailio.CallRegistry, call_id) != []

  # Registry unregisters on its own receipt of the call process's :DOWN, which
  # lags the command reply — poll rather than assume it's immediate.
  defp eventually_unregistered(call_id, tries \\ 50) do
    cond do
      not registered?(call_id) -> true
      tries == 0 -> false
      true -> Process.sleep(5) && eventually_unregistered(call_id, tries - 1)
    end
  end

  defp frame(cookie, payload) do
    cookie <> " " <> Bento.encode!(payload)
  end

  defp decode!(<<_cookie::binary-size(5), " ", body::binary>>) do
    {:ok, decoded} = Bento.decode(body)
    decoded
  end

  describe "ping" do
    test "responds with pong", %{state: state} do
      msg = frame("aaaaa", %{command: "ping"})

      assert {:push, {:text, reply}, _new_state} =
               WebSocket.handle_in({msg, [opcode: :text]}, state)

      assert decode!(reply) == %{"result" => "pong"}
    end
  end

  describe "offer" do
    test "invokes handler with parsed session and replies with the handler's SDP", %{state: state} do
      msg =
        frame("aaaaa", %{
          command: "offer",
          "call-id": "call-1",
          "from-tag": "f1",
          sdp: @offer_sdp
        })

      assert {:push, {:text, reply}, _state} =
               WebSocket.handle_in({msg, [opcode: :text]}, state)

      decoded = decode!(reply)
      assert decoded["result"] == "ok"
      assert is_binary(decoded["sdp"])
      assert decoded["sdp"] =~ "RTP/AVP 0 101"
      assert decoded["sdp"] =~ "m=audio 30000"

      assert_receive {:offer_called, session}
      assert session.call_id == "call-1"
      assert session.from_tag == "f1"
      assert %ExSDP{} = session.from_offerer_sdp
    end
  end

  describe "answer" do
    test "requires a prior offer", %{state: state} do
      msg =
        frame("aaaaa", %{
          command: "answer",
          "call-id": "no-such-call",
          "to-tag": "t1",
          sdp: @offer_sdp
        })

      assert {:push, {:text, reply}, _state} =
               WebSocket.handle_in({msg, [opcode: :text]}, state)

      assert decode!(reply)["result"] == "error"
    end

    test "completes a full offer/answer round trip", %{state: state} do
      offer_msg =
        frame("aaaaa", %{
          command: "offer",
          "call-id": "call-3",
          "from-tag": "f1",
          sdp: @offer_sdp
        })

      {:push, _, state} = WebSocket.handle_in({offer_msg, [opcode: :text]}, state)

      answer_msg =
        frame("aaaab", %{
          command: "answer",
          "call-id": "call-3",
          "to-tag": "t1",
          sdp: @offer_sdp
        })

      assert {:push, {:text, reply}, _state} =
               WebSocket.handle_in({answer_msg, [opcode: :text]}, state)

      assert decode!(reply)["result"] == "ok"
      assert_receive {:offer_called, _}
      assert_receive {:answer_called, session}
      assert session.to_tag == "t1"
      assert %ExSDP{} = session.to_answerer_sdp
    end
  end

  describe "delete" do
    test "invokes handler.delete and drops the call process", %{state: state} do
      offer_msg =
        frame("aaaaa", %{
          command: "offer",
          "call-id": "call-4",
          "from-tag": "f1",
          sdp: @offer_sdp
        })

      {:push, _, state} = WebSocket.handle_in({offer_msg, [opcode: :text]}, state)

      delete_msg = frame("aaaac", %{command: "delete", "call-id": "call-4"})

      assert {:push, {:text, reply}, _state} =
               WebSocket.handle_in({delete_msg, [opcode: :text]}, state)

      assert decode!(reply)["result"] == "ok"
      assert_receive {:offer_called, _}
      assert_receive {:delete_called, _}
      assert eventually_unregistered("call-4")
    end
  end

  defmodule MarkingHandler do
    use ExKamailio.CallHandler

    @local %ExKamailio.Endpoint{ip: "192.0.2.1", rtp_port: 30_000, rtcp_port: 30_001}

    @impl true
    def init(opts), do: {:ok, %{report_to: opts[:report_to], mark: nil}}

    @impl true
    def handle_offer(offer, session, state) do
      {:ok, SDP.rewrite_endpoint(offer, @local), %{state | mark: session.call_id}}
    end

    @impl true
    def handle_answer(answer, _session, state),
      do: {:ok, SDP.rewrite_endpoint(answer, @local), state}

    @impl true
    def handle_delete(session, state) do
      send(state.report_to, {:deleted, session.call_id, state.mark})
      {:ok, state}
    end
  end

  describe "per-call state" do
    test "interleaved calls keep independent state" do
      Application.put_env(:ex_kamailio, :handler, MarkingHandler)
      Application.put_env(:ex_kamailio, :handler_opts, report_to: self())
      {:ok, state} = WebSocket.init([])

      offer = fn cid, ftag ->
        frame("aaaaa", %{command: "offer", "call-id": cid, "from-tag": ftag, sdp: @offer_sdp})
      end

      {:push, _, state} = WebSocket.handle_in({offer.("call-A", "fa"), [opcode: :text]}, state)
      {:push, _, state} = WebSocket.handle_in({offer.("call-B", "fb"), [opcode: :text]}, state)

      del = fn cid -> frame("aaaac", %{command: "delete", "call-id": cid}) end
      {:push, _, state} = WebSocket.handle_in({del.("call-A"), [opcode: :text]}, state)
      {:push, _, _state} = WebSocket.handle_in({del.("call-B"), [opcode: :text]}, state)

      assert_receive {:deleted, "call-A", "call-A"}
      assert_receive {:deleted, "call-B", "call-B"}
    end

    test "a call survives across pooled connections (offer and delete on different WS)" do
      Application.put_env(:ex_kamailio, :handler, MarkingHandler)
      Application.put_env(:ex_kamailio, :handler_opts, report_to: self())

      {:ok, conn_a} = WebSocket.init([])
      {:ok, conn_b} = WebSocket.init([])

      offer =
        frame("aaaaa", %{command: "offer", "call-id": "call-X", "from-tag": "fx", sdp: @offer_sdp})

      {:push, _, _} = WebSocket.handle_in({offer, [opcode: :text]}, conn_a)

      delete = frame("aaaac", %{command: "delete", "call-id": "call-X"})
      {:push, _, _} = WebSocket.handle_in({delete, [opcode: :text]}, conn_b)

      assert_receive {:deleted, "call-X", "call-X"}
    end
  end

  defmodule CrashingHandler do
    use ExKamailio.CallHandler

    @impl true
    def handle_offer(_sdp, _s, _st), do: raise("boom")

    @impl true
    def handle_answer(_sdp, _s, _st), do: raise("boom")
  end

  describe "handler crash" do
    test "a raising offer becomes an error reply, not a WS process crash" do
      Application.put_env(:ex_kamailio, :handler, CrashingHandler)
      {:ok, state} = WebSocket.init([])

      msg =
        frame("aaaaa", %{
          command: "offer",
          "call-id": "call-crash",
          "from-tag": "f1",
          sdp: @offer_sdp
        })

      assert {:push, {:text, reply}, _state} =
               WebSocket.handle_in({msg, [opcode: :text]}, state)

      assert decode!(reply)["result"] == "error"
      assert eventually_unregistered("call-crash")
    end
  end

  describe "garbage in" do
    test "returns error for unknown command", %{state: state} do
      msg = frame("aaaaa", %{command: "wat"})

      assert {:push, {:text, reply}, _state} =
               WebSocket.handle_in({msg, [opcode: :text]}, state)

      assert decode!(reply)["result"] == "error"
    end

    test "returns error for non-Bencode body", %{state: state} do
      msg = "aaaaa not-bencode"

      assert {:push, {:text, reply}, _state} =
               WebSocket.handle_in({msg, [opcode: :text]}, state)

      assert decode!(reply)["result"] == "error"
    end
  end
end
