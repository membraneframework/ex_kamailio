defmodule RelayHandler.Pipeline do
  @moduledoc """
  A minimal two-peer RTP relay built from a pair of `Membrane.UDP.Endpoint`s
  wired crosswise.

      caller (UAC)  <--->  :caller_leg  <-x->  :callee_leg  <--->  callee (UAS)

  Each leg is bound to the local port the rtpengine protocol allocated for
  that direction and sends out toward *the opposite* party's SDP address:

  * `:caller_leg` is the "talk to the caller" socket. It listens on
    `callee_local` (the port the caller was told to send to in the rewritten
    answer SDP) and sends to `caller_remote` (the caller's SDP address).
  * `:callee_leg` is symmetric for the callee side.

  Output buffers from one leg are routed into the input of the other so that
  audio in flight from peer A is sent out the socket facing peer B.

  Limitations:
    * RTP only — RTCP is not relayed (would need a second pair of endpoints).
    * No latching — destinations come from each peer's SDP and are fixed for
      the call. Symmetric-NAT peers will not work without latching, which can
      be added by inspecting `udp_source_address`/`udp_source_port` on the
      output buffers and rewriting the opposite leg's destination.
  """

  use Membrane.Pipeline

  require Membrane.Logger
  alias Membrane.{Debug, UDP.Endpoint}
  alias ExKamailio.Endpoint, as: EkEndpoint

  @type opts :: %{
          call_id: String.t(),
          local_ip: :inet.socket_address(),
          caller_local: EkEndpoint.t(),
          caller_remote: EkEndpoint.t(),
          callee_local: EkEndpoint.t(),
          callee_remote: EkEndpoint.t()
        }

  @impl true
  def handle_init(_ctx, opts) do
    Membrane.Logger.info(
      "[relay] start call=#{opts.call_id} " <>
        "caller local=#{inspect(opts.caller_local)} remote=#{inspect(opts.caller_remote)} " <>
        "callee local=#{inspect(opts.callee_local)} remote=#{inspect(opts.callee_remote)}"
    )

    # The rtpengine wire convention: `caller_local` is the port advertised in
    # the rewritten *INVITE* — i.e. the port the *callee* sends to. Symmetric
    # for `callee_local`. So the leg that "talks to the caller" listens on
    # `callee_local` (where the caller's RTP lands) and sends out toward
    # `caller_remote`.
    caller_leg = %Endpoint{
      local_address: opts.local_ip,
      local_port_no: opts.callee_local.rtp_port,
      destination_address: opts.caller_remote.ip,
      destination_port_no: opts.caller_remote.rtp_port
    }

    callee_leg = %Endpoint{
      local_address: opts.local_ip,
      local_port_no: opts.caller_local.rtp_port,
      destination_address: opts.callee_remote.ip,
      destination_port_no: opts.callee_remote.rtp_port
    }

    caller_to_callee = :counters.new(1, [])
    callee_to_caller = :counters.new(1, [])

    spec = [
      # Caller → relay → callee:
      # caller's RTP arrives at :caller_leg, output goes through the probe,
      # then out :callee_leg toward the callee.
      child(:caller_leg, caller_leg)
      |> child(:probe_caller_to_callee, %Debug.Filter{handle_buffer: tally(caller_to_callee)})
      |> child(:callee_leg, callee_leg),
      # Callee → relay → caller: the mirror image.
      get_child(:callee_leg)
      |> child(:probe_callee_to_caller, %Debug.Filter{handle_buffer: tally(callee_to_caller)})
      |> get_child(:caller_leg)
    ]

    state = %{
      call_id: opts.call_id,
      caller_to_callee: caller_to_callee,
      callee_to_caller: callee_to_caller
    }

    {[spec: spec, start_timer: {:tally, Membrane.Time.second()}], state}
  end

  @impl true
  def handle_tick(:tally, _ctx, state) do
    a = :counters.get(state.caller_to_callee, 1)
    b = :counters.get(state.callee_to_caller, 1)

    Membrane.Logger.info(
      "[relay] call=#{state.call_id} caller→callee=#{a} pkts, callee→caller=#{b} pkts"
    )

    {[], state}
  end

  defp tally(counter) do
    fn _buffer -> :counters.add(counter, 1, 1) end
  end
end
