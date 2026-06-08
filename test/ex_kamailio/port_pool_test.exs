defmodule ExKamailio.PortPoolTest do
  use ExUnit.Case, async: false

  alias ExKamailio.PortPool

  setup do
    # Restart the pool with a tiny range so we can exhaust it.
    Application.put_env(:ex_kamailio, :port_range, 11_000..11_005)
    stop_supervised(PortPool)
    {:ok, _pid} = start_supervised(PortPool)
    :ok
  end

  test "checkout returns a pair of even ports" do
    assert {:ok, {a, b}} = PortPool.checkout(:call_one)
    assert rem(a, 2) == 0
    assert rem(b, 2) == 0
    assert a != b
  end

  test "release returns the port to the pool" do
    {:ok, {a, _b}} = PortPool.checkout(:call_one)
    assert :ok = PortPool.release(:call_one, a)
  end

  test "exhausting the pool returns :no_ports" do
    # 11_000..11_005 has even values: 11000, 11002, 11004 — one full pair plus one orphan.
    assert {:ok, _} = PortPool.checkout(:call_one)
    assert {:error, :no_ports} = PortPool.checkout(:call_two)
  end
end
