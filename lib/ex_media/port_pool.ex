defmodule ExMedia.PortPool do
  @moduledoc "Manages a pool of UDP port pairs (RTP/RTCP)."
  use GenServer


  ## API
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def checkout(key), do: GenServer.call(__MODULE__, {:checkout, key})
  def release(key, rtp), do: GenServer.call(__MODULE__, {:release, key, rtp})


  ## Server
  @impl true
  def init(_opts) do
    range = Application.fetch_env!(:ex_media, :port_range)
    available = range |> Enum.filter(&(rem(&1, 2) == 0)) |> :queue.from_list()
    {:ok, %{available: available, allocated: %{}, ip: Application.fetch_env!(:ex_media, :media_ip)}}
  end


  def handle_call({:checkout, key}, _from, %{available: q} = s) do
    case :queue.out(q) do
      {{:value, rtp1}, q2} ->
        case :queue.out(q2) do
          {{:value, rtp2}, q3} ->
            alloc = Map.put(s.allocated, key, %{rtp: {rtp1, rtp2}})
            {:reply, {:ok, {rtp1, rtp2}}, %{s | available: q3, allocated: alloc}}
          {_, _} ->
            # not enough ports left; put the first one back
            {:reply, {:error, :no_ports}, s}
        end
        {_, _} ->
          {:reply, {:error, :no_ports}, s}
    end
  end

  #@impl true
  #def handle_call({:checkout, key}, _from, %{available: q} = s) do
  #  case :queue.out(q) do
  #    {{:value, base}, q2} ->
  #      rtp = base
  #      rtcp = base + 1
  #      alloc = Map.put(s.allocated, key, %{rtp: rtp, rtcp: rtcp})
  #      {:reply, {:ok, {rtp, rtcp}}, %{s | available: q2, allocated: alloc}}
  #    {_, _} ->
  #      {:reply, {:error, :no_ports}, s}
  #  end
  #end


  @impl true
  def handle_call({:release, key, rtp}, _from, s) do
    {:reply, :ok, %{s | allocated: Map.delete(s.allocated, key), available: :queue.in(rtp, s.available)}}
  end


  #defp parse_ip(str) do
  #  case :inet.parse_address(String.to_charlist(str)) do
  #    {:ok, ip} -> ip
  #    _ -> {127,0,0,1}
  #  end
  #end
end
