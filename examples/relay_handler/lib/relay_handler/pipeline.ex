defmodule RelayHandler.Pipeline do
  @moduledoc """
  The media path of one call: a `Membrane.UDP.Endpoint` facing each peer,
  cross-linked so that whatever one peer sends goes out to the other.

  Both sockets are bound on `:offer`, before their ports get into any SDP.
  The offerer's address is known by then; the answerer's is set on `:answer`.
  Each direction is also recorded as raw RTP payload to
  `<recordings_dir>/<call_id>__<from>_to_<to>.raw`.
  """

  use Membrane.Pipeline

  alias Membrane.{RTP, Tee, UDP}

  # The answerer-facing socket needs a destination before the answer comes;
  # the discard port keeps anything sent in the meantime from going anywhere.
  @nowhere {{127, 0, 0, 1}, 9}

  @impl true
  def handle_init(_ctx, call_id) do
    recordings_dir = Application.fetch_env!(:relay_handler, :recordings_dir)
    File.mkdir_p!(recordings_dir)
    prefix = Path.join(recordings_dir, String.replace(call_id, ~r/[^\w.@-]/, "_"))
    {[], %{prefix: prefix, ports: %{}, from: nil}}
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

  # :offer is answered once both sockets report the ports they got.
  @impl true
  def handle_child_notification({:connection_info, _ip, port}, {:socket, peer}, _ctx, state) do
    ports = Map.put(state.ports, peer, port)
    reply = if map_size(ports) == 2, do: [reply_to: {state.from, ports}], else: []
    {reply, %{state | ports: ports}}
  end

  defp socket(peer, {ip, port}) do
    child({:socket, peer}, %UDP.Endpoint{destination_address: ip, destination_port_no: port})
    |> child({:tee, peer}, Tee)
  end

  defp recording(link, prefix, direction) do
    link
    |> child({:parser, direction}, RTP.Parser)
    |> child({:file, direction}, %Membrane.File.Sink{location: "#{prefix}__#{direction}.raw"})
  end
end
