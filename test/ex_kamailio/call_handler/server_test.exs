defmodule ExKamailio.CallHandler.ServerTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log

  alias ExKamailio.Session
  alias ExKamailio.CallHandler

  defmodule ApiHandler do
    use ExKamailio.CallHandler

    @impl true
    def init(opts), do: {:ok, %{report_to: opts[:report_to]}}

    @impl true
    def handle_offer(_offer, session, st) do
      send(st.report_to, {:offer, session.call_id})
      {:ok, ExSDP.new(), st}
    end

    @impl true
    def handle_answer(_answer, session, st) do
      send(st.report_to, {:answer, session.call_id, session.to_tag})
      {:ok, ExSDP.new(), st}
    end

    @impl true
    def handle_delete(session, st) do
      send(st.report_to, {:delete, session.call_id})
      {:ok, st}
    end

    @impl true
    def handle_info(msg, session, st) do
      send(st.report_to, {:info, session.call_id, msg})
      {:ok, st}
    end
  end

  defmodule MinimalHandler do
    use ExKamailio.CallHandler

    @impl true
    def handle_offer(_offer, _session, st), do: {:ok, ExSDP.new(), st}

    @impl true
    def handle_answer(_answer, _session, st), do: {:ok, ExSDP.new(), st}
  end

  defmodule ExtendHandler do
    use ExKamailio.CallHandler

    @impl true
    def init(opts), do: {:ok, %{report_to: opts[:report_to]}}

    @impl true
    def handle_offer(_offer, _session, st), do: {:ok, ExSDP.new(), st}

    @impl true
    def handle_answer(_answer, _session, st), do: {:ok, ExSDP.new(), st}

    @impl true
    def handle_timeout(session, st) do
      send(st.report_to, {:timeout, session.call_id})
      {:noreply, st}
    end
  end

  defmodule SlowHandler do
    use ExKamailio.CallHandler

    @impl true
    def init(opts), do: {:ok, %{report_to: opts[:report_to]}}

    @impl true
    def handle_offer(_offer, _session, st) do
      Process.sleep(200)
      {:ok, ExSDP.new(), st}
    end

    @impl true
    def handle_answer(_answer, _session, st), do: {:ok, ExSDP.new(), st}

    @impl true
    def handle_delete(session, st) do
      send(st.report_to, {:delete, session.call_id})
      {:ok, st}
    end
  end

  defmodule CrashHandler do
    use ExKamailio.CallHandler

    @impl true
    def handle_offer(_offer, _session, _st), do: raise("boom")

    @impl true
    def handle_answer(_answer, _session, st), do: {:ok, ExSDP.new(), st}
  end

  setup do
    start_supervised!({Registry, keys: :unique, name: ExKamailio.CallRegistry})

    start_supervised!(
      {DynamicSupervisor, name: ExKamailio.CallSupervisor, strategy: :one_for_one}
    )

    :ok
  end

  defp offer_session(call_id) do
    %Session{call_id: call_id, from_tag: "f-#{call_id}"}
  end

  defp answer_fields(to_tag) do
    %{to_tag: to_tag, from_answerer_sdp: nil}
  end

  defp registered?(call_id), do: Registry.lookup(ExKamailio.CallRegistry, call_id) != []

  # Registry unregisters on its own receipt of the call process's :DOWN, which
  # lags GenServer.call returning — poll rather than assume it's immediate.
  defp eventually_unregistered(call_id, tries \\ 50) do
    cond do
      not registered?(call_id) -> true
      tries == 0 -> false
      true -> Process.sleep(5) && eventually_unregistered(call_id, tries - 1)
    end
  end

  test "offer/answer/delete round trip threads through one process" do
    {:ok, _} = CallHandler.Server.start_call("c1", ApiHandler, report_to: self())

    assert {:ok, offer_reply} = CallHandler.Server.call_offer("c1", offer_session("c1"))
    assert is_binary(offer_reply)
    assert_receive {:offer, "c1"}

    assert {:ok, answer_reply} = CallHandler.Server.call_answer("c1", answer_fields("t1"))
    assert is_binary(answer_reply)
    assert_receive {:answer, "c1", "t1"}

    assert :ok = CallHandler.Server.call_delete("c1")
    assert_receive {:delete, "c1"}
    assert eventually_unregistered("c1")
  end

  test "a retransmitted offer replays the cached reply without re-invoking the handler" do
    {:ok, _} = CallHandler.Server.start_call("c2a", ApiHandler, report_to: self())

    assert {:ok, reply} = CallHandler.Server.call_offer("c2a", offer_session("c2a"))
    assert_receive {:offer, "c2a"}

    assert {:ok, ^reply} = CallHandler.Server.call_offer("c2a", offer_session("c2a"))
    refute_receive {:offer, "c2a"}
  end

  test "a retransmitted answer replays the cached reply without re-invoking the handler" do
    {:ok, _} = CallHandler.Server.start_call("c2", ApiHandler, report_to: self())
    {:ok, _} = CallHandler.Server.call_offer("c2", offer_session("c2"))

    assert {:ok, reply} = CallHandler.Server.call_answer("c2", answer_fields("t1"))
    assert_receive {:answer, "c2", "t1"}

    assert {:ok, ^reply} = CallHandler.Server.call_answer("c2", answer_fields("t1"))
    refute_receive {:answer, "c2", "t1"}
  end

  test "two calls keep independent state in their own processes" do
    {:ok, _} = CallHandler.Server.start_call("a", ApiHandler, report_to: self())
    {:ok, _} = CallHandler.Server.start_call("b", ApiHandler, report_to: self())

    {:ok, _} = CallHandler.Server.call_offer("a", offer_session("a"))
    {:ok, _} = CallHandler.Server.call_offer("b", offer_session("b"))

    assert :ok = CallHandler.Server.call_delete("a")
    assert_receive {:delete, "a"}
    assert registered?("b")

    assert :ok = CallHandler.Server.call_delete("b")
    assert_receive {:delete, "b"}
  end

  test "handle_info/3 is delivered with the call's session" do
    {:ok, pid} = CallHandler.Server.start_call("c3", ApiHandler, report_to: self())
    {:ok, _} = CallHandler.Server.call_offer("c3", offer_session("c3"))

    send(pid, :ping_from_pipeline)
    assert_receive {:info, "c3", :ping_from_pipeline}
  end

  test "a stray message to a handler without handle_info/3 crashes only that call" do
    {:ok, pid} = CallHandler.Server.start_call("c4", MinimalHandler, [])
    {:ok, _} = CallHandler.Server.call_offer("c4", offer_session("c4"))
    ref = Process.monitor(pid)

    send(pid, :stray)
    assert_receive {:DOWN, ^ref, :process, ^pid, {:undef, _}}
    assert eventually_unregistered("c4")
  end

  test "the default handle_timeout reaps the call: runs delete then stops" do
    prev = Application.get_env(:ex_kamailio, :call_timeout)
    Application.put_env(:ex_kamailio, :call_timeout, 50)
    on_exit(fn -> Application.put_env(:ex_kamailio, :call_timeout, prev) end)

    {:ok, pid} = CallHandler.Server.start_call("c5", ApiHandler, report_to: self())
    ref = Process.monitor(pid)
    {:ok, _} = CallHandler.Server.call_offer("c5", offer_session("c5"))

    assert_receive {:delete, "c5"}, 500
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    assert eventually_unregistered("c5")
  end

  test "a custom handle_timeout returning :noreply keeps the call alive" do
    prev = Application.get_env(:ex_kamailio, :call_timeout)
    Application.put_env(:ex_kamailio, :call_timeout, 50)
    on_exit(fn -> Application.put_env(:ex_kamailio, :call_timeout, prev) end)

    {:ok, _} = CallHandler.Server.start_call("c6", ExtendHandler, report_to: self())
    {:ok, _} = CallHandler.Server.call_offer("c6", offer_session("c6"))

    assert_receive {:timeout, "c6"}, 500
    assert registered?("c6")
  end

  test "an offer that misses the reply deadline errors in time, then the call tears down" do
    prev = Application.get_env(:ex_kamailio, :rtpengine_command_timeout)
    Application.put_env(:ex_kamailio, :rtpengine_command_timeout, 50)
    on_exit(fn -> Application.put_env(:ex_kamailio, :rtpengine_command_timeout, prev) end)

    {:ok, pid} = CallHandler.Server.start_call("c8", SlowHandler, report_to: self())
    ref = Process.monitor(pid)

    assert {:error, :timeout} = CallHandler.Server.call_offer("c8", offer_session("c8"))
    assert_receive {:delete, "c8"}, 500
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    assert eventually_unregistered("c8")
  end

  test "a crashing offer becomes {:error, _} and leaves no registered process" do
    {:ok, _} = CallHandler.Server.start_call("c7", CrashHandler, [])

    assert {:error, _} = CallHandler.Server.call_offer("c7", offer_session("c7"))
    assert eventually_unregistered("c7")
  end

  test "calls for an unknown call_id return {:error, :unknown}" do
    assert {:error, :unknown} = CallHandler.Server.call_answer("nope", answer_fields("t1"))
    assert {:error, :unknown} = CallHandler.Server.call_delete("nope")
  end
end
