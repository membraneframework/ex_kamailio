defmodule ExKamailio.SessionTableTest do
  use ExUnit.Case, async: false

  alias ExKamailio.{Session, SessionTable}

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
end
