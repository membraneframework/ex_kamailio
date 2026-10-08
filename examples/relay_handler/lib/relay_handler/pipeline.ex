defmodule RelayHandler.Pipeline do
  @moduledoc """
  The media path of one call: a `Membrane.UDP.Endpoint` facing each peer,
  cross-linked so that whatever one peer sends goes out to the other.

  `offer/2` binds both sockets, before their ports get into any SDP, and aims
  the offerer-facing one at the offerer; `answer/2` aims the other at the
  answerer. Either address is only where the first packets go: each socket
  then latches onto the source of what it receives, which is what gets
  through a peer's NAT. Each direction is also recorded as raw RTP payload to
  `<recordings_dir>/<call_id>__<from>_to_<to>.raw`.
  """

  use Membrane.Pipeline

  alias Membrane.{RTP, Tee, UDP}

  @type address :: {:inet.ip_address(), :inet.port_number()}

  # A destination for the answerer-facing socket until the answer comes: the discard port.
  @nowhere {{127, 0, 0, 1}, 9}

  @spec start_link(call_id :: String.t()) :: Membrane.Pipeline.on_start()
  def start_link(call_id), do: Membrane.Pipeline.start_link(__MODULE__, call_id)

  @spec offer(pid(), address()) :: %{offerer: :inet.port_number(), answerer: :inet.port_number()}
  def offer(pipeline, offerer), do: Membrane.Pipeline.call(pipeline, {:offer, offerer})

  @spec answer(pid(), address()) :: :ok
  def answer(pipeline, answerer), do: Membrane.Pipeline.call(pipeline, {:answer, answerer})

  @spec terminate(pid()) :: :ok | {:error, :timeout}
  def terminate(pipeline), do: Membrane.Pipeline.terminate(pipeline)

  @impl true
  def handle_init(_ctx, call_id) do
    recordings_dir = Application.fetch_env!(:relay_handler, :recordings_dir)
    File.mkdir_p!(recordings_dir)
    file_name = String.replace(call_id, ~r/[^\w.@-]/, "_")
    {[], %{prefix: Path.join(recordings_dir, file_name), ports: %{}, from: nil}}
  end

  @impl true
  def handle_call({:offer, offerer}, ctx, state) do
    spec = [
      socket(:offerer, offerer),
      socket(:answerer, @nowhere),
      get_child({:tee, :offerer}) |> get_child({:socket, :answerer}),
      get_child({:tee, :answerer}) |> get_child({:socket, :offerer}),
      get_child({:tee, :offerer}) |> recording(state.prefix, "offerer_to_answerer"),
      get_child({:tee, :answerer}) |> recording(state.prefix, "answerer_to_offerer")
    ]

    {[spec: spec], %{state | from: ctx.from}}
  end

  @impl true
  def handle_call({:answer, {ip, port}}, _ctx, state) do
    {[notify_child: {{:socket, :answerer}, {:set_destination, ip, port}}, reply: :ok], state}
  end

  # offer/2 returns once both sockets report their ports.
  @impl true
  def handle_child_notification({:connection_info, _ip, port}, {:socket, peer}, _ctx, state) do
    ports = Map.put(state.ports, peer, port)
    reply = if map_size(ports) == 2, do: [reply_to: {state.from, ports}], else: []
    {reply, %{state | ports: ports}}
  end

  defp socket(peer, {ip, port}) do
    endpoint = %UDP.Endpoint{destination_address: ip, destination_port_no: port, latch?: true}

    child({:socket, peer}, endpoint)
    |> child({:tee, peer}, Tee)
  end

  defp recording(link, prefix, direction) do
    link
    |> child({:parser, direction}, RTP.Parser)
    |> child({:file, direction}, %Membrane.File.Sink{location: "#{prefix}__#{direction}.raw"})
  end
end
