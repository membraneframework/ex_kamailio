defmodule ExKamailio.CallHandler.ServerTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log

  alias ExKamailio.CallHandler
  alias ExKamailio.Session

  alias ExKamailio.TestHandlers.{
    ApiHandler,
    CrashHandler,
    ExtendHandler,
    InitSessionHandler,
    MinimalHandler,
    SlowHandler
  }

  setup do
    start_supervised!(
      {Registry, keys: :unique, name: ExKamailio.ConstantsAndConfig.call_registry()}
    )

    start_supervised!(
      {DynamicSupervisor,
       name: ExKamailio.ConstantsAndConfig.call_supervisor(), strategy: :one_for_one}
    )

    :ok
  end

  defp start_call(call_id, from_tag, impl, impl_opts) do
    CallHandler.Server.start_call(%{
      call_id: call_id,
      from_tag: from_tag,
      impl: impl,
      impl_opts: impl_opts
    })
  end

  defp offer_session(call_id) do
    %Session{call_id: call_id, from_tag: "f-#{call_id}"}
  end

  defp answer_fields(to_tag) do
    %{to_tag: to_tag, from_answerer_sdp: nil}
  end

  defp registered?(call_id),
    do: Registry.lookup(ExKamailio.ConstantsAndConfig.call_registry(), call_id) != []

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
    {:ok, _} = start_call("c1", "f-c1", ApiHandler, report_to: self())

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
    {:ok, _} = start_call("c2a", "f-c2a", ApiHandler, report_to: self())

    assert {:ok, reply} = CallHandler.Server.call_offer("c2a", offer_session("c2a"))
    assert_receive {:offer, "c2a"}

    assert {:ok, ^reply} = CallHandler.Server.call_offer("c2a", offer_session("c2a"))
    refute_receive {:offer, "c2a"}
  end

  test "a retransmitted answer replays the cached reply without re-invoking the handler" do
    {:ok, _} = start_call("c2", "f-c2", ApiHandler, report_to: self())
    {:ok, _} = CallHandler.Server.call_offer("c2", offer_session("c2"))

    assert {:ok, reply} = CallHandler.Server.call_answer("c2", answer_fields("t1"))
    assert_receive {:answer, "c2", "t1"}

    assert {:ok, ^reply} = CallHandler.Server.call_answer("c2", answer_fields("t1"))
    refute_receive {:answer, "c2", "t1"}
  end

  test "two calls keep independent state in their own processes" do
    {:ok, _} = start_call("a", "f-a", ApiHandler, report_to: self())
    {:ok, _} = start_call("b", "f-b", ApiHandler, report_to: self())

    {:ok, _} = CallHandler.Server.call_offer("a", offer_session("a"))
    {:ok, _} = CallHandler.Server.call_offer("b", offer_session("b"))

    assert :ok = CallHandler.Server.call_delete("a")
    assert_receive {:delete, "a"}
    assert registered?("b")

    assert :ok = CallHandler.Server.call_delete("b")
    assert_receive {:delete, "b"}
  end

  test "handle_info/3 is delivered with the call's session" do
    {:ok, pid} = start_call("c3", "f-c3", ApiHandler, report_to: self())
    {:ok, _} = CallHandler.Server.call_offer("c3", offer_session("c3"))

    send(pid, :ping_from_pipeline)
    assert_receive {:info, "c3", :ping_from_pipeline}
  end

  test "a stray message to a handler without a custom handle_info/3 is ignored" do
    {:ok, pid} = start_call("c4", "f-c4", MinimalHandler, [])
    {:ok, _} = CallHandler.Server.call_offer("c4", offer_session("c4"))
    ref = Process.monitor(pid)

    send(pid, :stray)
    refute_receive {:DOWN, ^ref, :process, ^pid, _}
    assert registered?("c4")
  end

  test "the default handle_idle reaps the call: runs delete then stops" do
    prev = Application.get_env(:ex_kamailio, :idle_timeout)
    Application.put_env(:ex_kamailio, :idle_timeout, 50)
    on_exit(fn -> Application.put_env(:ex_kamailio, :idle_timeout, prev) end)

    {:ok, pid} = start_call("c5", "f-c5", ApiHandler, report_to: self())
    ref = Process.monitor(pid)
    {:ok, _} = CallHandler.Server.call_offer("c5", offer_session("c5"))

    assert_receive {:delete, "c5"}, 500
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    assert eventually_unregistered("c5")
  end

  test "a custom handle_idle returning {:ok, state} keeps the call alive" do
    prev = Application.get_env(:ex_kamailio, :idle_timeout)
    Application.put_env(:ex_kamailio, :idle_timeout, 50)
    on_exit(fn -> Application.put_env(:ex_kamailio, :idle_timeout, prev) end)

    {:ok, _} = start_call("c6", "f-c6", ExtendHandler, report_to: self())
    {:ok, _} = CallHandler.Server.call_offer("c6", offer_session("c6"))

    assert_receive {:idle, "c6"}, 500
    assert registered?("c6")
  end

  test "an offer that misses the reply deadline errors in time, then the call tears down" do
    prev = Application.get_env(:ex_kamailio, :callback_timeout)
    Application.put_env(:ex_kamailio, :callback_timeout, 50)
    on_exit(fn -> Application.put_env(:ex_kamailio, :callback_timeout, prev) end)

    {:ok, pid} = start_call("c8", "f-c8", SlowHandler, report_to: self())
    ref = Process.monitor(pid)

    assert {:error, :timeout} = CallHandler.Server.call_offer("c8", offer_session("c8"))
    assert_receive {:delete, "c8"}, 500
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    assert eventually_unregistered("c8")
  end

  test "a crashing offer becomes {:error, _} and leaves no registered process" do
    {:ok, _} = start_call("c7", "f-c7", CrashHandler, [])

    assert {:error, _} = CallHandler.Server.call_offer("c7", offer_session("c7"))
    assert eventually_unregistered("c7")
  end

  test "init receives a session with call_id and from_tag set, SDPs not yet" do
    {:ok, _} = start_call("c9", "tag-9", InitSessionHandler, report_to: self())

    assert_receive {:init_session, session}
    assert session.call_id == "c9"
    assert session.from_tag == "tag-9"
    assert session.to_tag == nil
    assert session.from_offerer_sdp == nil
  end

  test "calls for an unknown call_id return {:error, :unknown}" do
    assert {:error, :unknown} = CallHandler.Server.call_answer("nope", answer_fields("t1"))
    assert {:error, :unknown} = CallHandler.Server.call_delete("nope")
  end
end
