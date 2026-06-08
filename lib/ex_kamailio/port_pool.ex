defmodule ExKamailio.PortPool do
  @moduledoc """
  Manages a pool of UDP port pairs (RTP + RTCP).

  Allocates even-numbered ports (the canonical RTP port; RTCP is the
  next odd port). Configured by the `:port_range` application env.
  """

  use GenServer

  @type key :: term()

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Reserve a pair of consecutive even ports for the given key.

  Returns `{:ok, {rtp_a, rtp_b}}` where each value is the even RTP port
  of its pair (RTCP is `port + 1`).
  """
  @spec checkout(key()) :: {:ok, {pos_integer(), pos_integer()}} | {:error, :no_ports}
  def checkout(key), do: GenServer.call(__MODULE__, {:checkout, key})

  @doc "Release a previously checked-out RTP port."
  @spec release(key(), pos_integer()) :: :ok
  def release(key, rtp), do: GenServer.call(__MODULE__, {:release, key, rtp})

  @impl true
  def init(_opts) do
    range = Application.fetch_env!(:ex_kamailio, :port_range)
    available = range |> Enum.filter(&(rem(&1, 2) == 0)) |> :queue.from_list()
    {:ok, %{available: available, allocated: %{}}}
  end

  @impl true
  def handle_call({:checkout, key}, _from, %{available: q} = s) do
    with {{:value, rtp1}, q2} <- :queue.out(q),
         {{:value, rtp2}, q3} <- :queue.out(q2) do
      alloc = Map.put(s.allocated, key, %{rtp: {rtp1, rtp2}})
      {:reply, {:ok, {rtp1, rtp2}}, %{s | available: q3, allocated: alloc}}
    else
      _ -> {:reply, {:error, :no_ports}, s}
    end
  end

  def handle_call({:release, key, rtp}, _from, s) do
    {:reply, :ok,
     %{s | allocated: Map.delete(s.allocated, key), available: :queue.in(rtp, s.available)}}
  end
end
