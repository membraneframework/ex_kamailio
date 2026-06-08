defmodule ExKamailio.SessionTableTest do
  use ExUnit.Case, async: false

  alias ExKamailio.{Endpoint, PortPool, Session, SessionTable}

  defmodule GcHandler do
    @behaviour ExKamailio.Handler

    @impl true
    def init(_opts), do: {:ok, %{}}

    @impl true
    def offer(_s, st), do: {:ok, "", st}

    @impl true
    def answer(_s, st), do: {:ok, "", st}

    @impl true
    def delete(_session, state) do
      send(state.report_to, :gc_deleted)
      {:ok, state}
    end
  end

  setup do
    stop_supervised(SessionTable)
    {:ok, _pid} = start_supervised(SessionTable)
    :ok
  end

  test "put/get round trip" do
    session = %Session{call_id: "abc", from_tag: "f1", state: :offered}
    assert :ok = SessionTable.put(session)
    assert %Session{call_id: "abc", from_tag: "f1", state: :offered} = SessionTable.get("abc")
  end

  test "get returns nil for an unknown call-id" do
    assert SessionTable.get("missing") == nil
  end

  test "delete removes the session" do
    SessionTable.put(%Session{call_id: "abc", from_tag: "f1", state: :offered})
    assert :ok = SessionTable.delete("abc")
    assert SessionTable.get("abc") == nil
  end

  test "put stamps :touched_at" do
    SessionTable.put(%Session{call_id: "abc"})
    assert is_integer(SessionTable.get("abc").touched_at)
  end

  test "gc reaps a stale session: runs handler.delete and releases its ports" do
    Application.put_env(:ex_kamailio, :port_range, 40_000..40_010)
    Application.put_env(:ex_kamailio, :handler, GcHandler)
    stop_supervised(PortPool)
    {:ok, _} = start_supervised(PortPool)

    {:ok, {rtp, _}} = PortPool.checkout({"stale", "f1"})
    assert Map.has_key?(:sys.get_state(PortPool).allocated, {"stale", "f1"})

    stale = %Session{
      call_id: "stale",
      from_tag: "f1",
      state: :offered,
      caller_local: %Endpoint{ip: {127, 0, 0, 1}, rtp_port: rtp, rtcp_port: rtp + 1},
      handler_state: %{report_to: self()},
      touched_at: System.monotonic_time(:second) - 31 * 60
    }

    :ets.insert(:ex_kamailio_sessions, {"stale", stale})

    send(SessionTable, :gc)
    # synchronous call flushes the :gc message ahead of it (same mailbox, FIFO)
    :sys.get_state(SessionTable)

    assert_receive :gc_deleted
    assert SessionTable.get("stale") == nil
    refute Map.has_key?(:sys.get_state(PortPool).allocated, {"stale", "f1"})
  end
end
