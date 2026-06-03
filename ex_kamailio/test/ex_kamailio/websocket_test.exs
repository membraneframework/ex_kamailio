defmodule ExKamailio.WebSocketTest do
  use ExUnit.Case, async: false

  alias ExKamailio.{PortPool, SDP, SessionTable, WebSocket}

  defmodule TestHandler do
    @behaviour ExKamailio.Handler

    @impl true
    def init(opts), do: {:ok, %{calls: opts[:report_to] || self()}}

    @impl true
    def offer(session, state) do
      send(state.calls, {:offer_called, session})
      # Return an %ExSDP{} struct (the canonical API) — the library serializes it.
      {:ok, SDP.rewrite_endpoint(session.offer_sdp, session.caller_local), state}
    end

    @impl true
    def answer(session, state) do
      send(state.calls, {:answer_called, session})
      {:ok, SDP.rewrite_endpoint(session.answer_sdp, session.callee_local), state}
    end

    @impl true
    def delete(session, state) do
      send(state.calls, {:delete_called, session})
      {:ok, state}
    end
  end

  defmodule RejectingHandler do
    @behaviour ExKamailio.Handler

    @impl true
    def init(_opts), do: {:ok, %{}}

    @impl true
    def offer(_s, st), do: {:error, :nope, st}

    @impl true
    def answer(_s, st), do: {:error, :nope, st}

    @impl true
    def delete(_s, st), do: {:ok, st}
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
    Application.put_env(:ex_kamailio, :media_ip, "192.0.2.1")
    Application.put_env(:ex_kamailio, :allowed_pts, [0, 101])
    Application.put_env(:ex_kamailio, :port_range, 30_000..30_020)

    stop_supervised(PortPool)
    stop_supervised(SessionTable)
    {:ok, _} = start_supervised(PortPool)
    {:ok, _} = start_supervised(SessionTable)

    {:ok, state} = WebSocket.init([])
    {:ok, state: state}
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
    test "invokes handler with parsed session and replies with allocated ports", %{state: state} do
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
      assert is_integer(decoded["rtp_port"])
      assert decoded["rtcp_port"] == decoded["rtp_port"] + 1
      # reply SDP is a serialized string carrying the offered codecs (forwarded)
      assert is_binary(decoded["sdp"])
      assert decoded["sdp"] =~ "RTP/AVP 0 101"

      assert_receive {:offer_called, session}
      assert session.call_id == "call-1"
      assert session.from_tag == "f1"
      assert session.state == :offered
      assert session.caller_local.rtp_port == decoded["rtp_port"]
      assert session.caller_remote.rtp_port == 49_170
    end

    test "rejects offer when handler returns :error", %{state: _state} do
      Application.put_env(:ex_kamailio, :handler, RejectingHandler)
      {:ok, state} = WebSocket.init([])

      msg =
        frame("aaaaa", %{
          command: "offer",
          "call-id": "call-2",
          "from-tag": "f1",
          sdp: @offer_sdp
        })

      assert {:push, {:text, reply}, _state} =
               WebSocket.handle_in({msg, [opcode: :text]}, state)

      assert decode!(reply)["result"] == "error"
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
      assert session.state == :answered
      assert session.to_tag == "t1"
    end
  end

  describe "delete" do
    test "invokes handler.delete and releases the session", %{state: state} do
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
      assert SessionTable.get("call-4") == nil
    end
  end

  defmodule MarkingHandler do
    @behaviour ExKamailio.Handler

    @impl true
    def init(opts), do: {:ok, %{report_to: opts[:report_to], mark: nil}}

    @impl true
    def offer(session, state) do
      reply = SDP.rewrite_endpoint(session.offer_sdp, session.caller_local)
      {:ok, reply, %{state | mark: session.call_id}}
    end

    @impl true
    def answer(session, state),
      do: {:ok, SDP.rewrite_endpoint(session.answer_sdp, session.callee_local), state}

    @impl true
    def delete(session, state) do
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

      # Two calls offered back-to-back over the same connection.
      {:push, _, state} = WebSocket.handle_in({offer.("call-A", "fa"), [opcode: :text]}, state)
      {:push, _, state} = WebSocket.handle_in({offer.("call-B", "fb"), [opcode: :text]}, state)

      del = fn cid -> frame("aaaac", %{command: "delete", "call-id": cid}) end
      {:push, _, state} = WebSocket.handle_in({del.("call-A"), [opcode: :text]}, state)
      {:push, _, _state} = WebSocket.handle_in({del.("call-B"), [opcode: :text]}, state)

      # Each delete sees its OWN call's mark, not the last-written one.
      assert_receive {:deleted, "call-A", "call-A"}
      assert_receive {:deleted, "call-B", "call-B"}
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
