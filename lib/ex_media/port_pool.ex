defmodule ExMedia.PortPool do
  @moduledoc "Manages a pool of UDP port pairs (RTP/RTCP)."
  use GenServer


  ## API
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def checkout(key), do: GenServer.call(__MODULE__, {:checkout, key})
  def release(key, {rtp, _rtcp}), do: GenServer.call(__MODULE__, {:release, key, rtp})


  ## Server
  @impl true
  def init(_opts) do
    range = Application.fetch_env!(:ex_media, :port_range)
    available = range |> Enum.filter(&(rem(&1, 2) == 0)) |> :queue.from_list()
    {:ok, %{available: available, allocated: %{}, ip: Application.fetch_env!(:ex_media, :media_ip)}}
  end


  @impl true
  def handle_call({:checkout, key}, _from, %{available: q} = s) do
    case :queue.out(q) do
      {{:value, base}, q2} ->
        rtp = base
        rtcp = base + 1
        with {:ok, rtp_sock} <- open_udp(rtp, s.ip),
             {:ok, rtcp_sock} <- open_udp(rtcp, s.ip) do
          alloc = Map.put(s.allocated, key, %{rtp: rtp, rtcp: rtcp, rtp_sock: rtp_sock, rtcp_sock: rtcp_sock})
          {:reply, {:ok, {rtp, rtcp, rtp_sock, rtcp_sock}}, %{s | available: q2, allocated: alloc}}
        else
          {:error, _} = e -> {:reply, e, %{s | available: :queue.in_r(base, q2)}}
        end
      {_, _} -> {:reply, {:error, :no_ports}, s}
end
end


  @impl true
  def handle_call({:release, key, rtp}, _from, s) do
    {:reply, :ok, %{s | allocated: Map.delete(s.allocated, key), available: :queue.in(rtp, s.available)}}
  end


  defp open_udp(port, ip) do
    opts = [:binary, {:ip, parse_ip(ip)}, {:active, false}, {:reuseaddr, true}]
    :gen_udp.open(port, opts)
  end


  defp parse_ip(str) do
    case :inet.parse_address(String.to_charlist(str)) do
      {:ok, ip} -> ip
      _ -> {127,0,0,1}
    end
  end
end
