defmodule RelayHandler.Pipeline do
  @moduledoc """
  A minimal two-peer RTP relay built from a pair of `Membrane.UDP.Endpoint`s
  wired crosswise. Each leg's output is fanned out through a
  `Tee.Parallel`: one branch forwards toward the other peer, the
  other branch strips RTP headers and writes the codec payload to
  `/recordings/<call_id>__<direction>.raw` — proof, on disk, that the
  bytes actually flowed through the Membrane pipeline.

      caller (UAC)  <---> :caller_leg <-> :tee_c2c -> probe -> :callee_leg <---> callee (UAS)
                                              \-> :parser -> :file (caller→callee.raw)

      callee        <--- :callee_leg <-> :tee_l2l -> probe -> :caller_leg ---> caller
                                              \-> :parser -> :file (callee→caller.raw)

  Each leg is bound to the local port the rtpengine protocol allocated for
  that direction and sends out toward *the opposite* party's SDP address:

  * `:caller_leg` is the "talk to the caller" socket. It listens on
    `callee_local` (the port the caller was told to send to in the rewritten
    answer SDP) and sends to `caller_remote` (the caller's SDP address).
  * `:callee_leg` is symmetric for the callee side.

  Both legs run with `latch?: true`, so each leg's outbound destination
  starts at the address from the peer's SDP and then follows whatever source
  the last inbound packet on that leg arrived from — the symmetric-RTP /
  NAT-traversal behaviour rtpengine itself provides.

  The recording files contain raw codec payload (RTP headers stripped). The
  relay forwards whatever codec the two peers negotiate between themselves —
  ex_kamailio just repoints their SDP at this box, it doesn't pick codecs. For
  plain softphone-to-softphone calls that's almost always PCMU (G.711 μ-law,
  PT 0), so the recordings are μ-law, 8 kHz, mono:

      ffplay -f mulaw -ar 8000 -ch_layout mono <call_id>__caller_to_callee.raw

  Limitations:
    * RTP only — RTCP is not relayed.
  """

  use Membrane.Pipeline

  require Membrane.Logger
  alias Membrane.{Debug, RTP, Tee, UDP.Endpoint}
  alias Membrane.File, as: MFile
  alias ExKamailio.Endpoint, as: EkEndpoint

  @recordings_dir "/recordings"

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
      destination_port_no: opts.caller_remote.rtp_port,
      latch?: true
    }

    callee_leg = %Endpoint{
      local_address: opts.local_ip,
      local_port_no: opts.caller_local.rtp_port,
      destination_address: opts.callee_remote.ip,
      destination_port_no: opts.callee_remote.rtp_port,
      latch?: true
    }

    caller_to_callee = :counters.new(1, [])
    callee_to_caller = :counters.new(1, [])

    safe_id = sanitize_call_id(opts.call_id)
    File.mkdir_p!(@recordings_dir)
    c2c_path = Path.join(@recordings_dir, "#{safe_id}__caller_to_callee.raw")
    l2l_path = Path.join(@recordings_dir, "#{safe_id}__callee_to_caller.raw")

    Membrane.Logger.info("[relay] recording call=#{opts.call_id} to #{c2c_path} / #{l2l_path}")

    spec = [
      child(:caller_leg, caller_leg)
      |> child(:tee_caller_to_callee, Tee.Parallel),
      get_child(:tee_caller_to_callee)
      |> child(:probe_caller_to_callee, %Debug.Filter{handle_buffer: tally(caller_to_callee)})
      |> child(:callee_leg, callee_leg),
      get_child(:tee_caller_to_callee)
      |> child(:parser_caller_to_callee, RTP.Parser)
      |> child(:writer_caller_to_callee, %MFile.Sink{location: c2c_path}),
      get_child(:callee_leg)
      |> child(:tee_callee_to_caller, Tee.Parallel),
      get_child(:tee_callee_to_caller)
      |> child(:probe_callee_to_caller, %Debug.Filter{handle_buffer: tally(callee_to_caller)})
      |> get_child(:caller_leg),
      get_child(:tee_callee_to_caller)
      |> child(:parser_callee_to_caller, RTP.Parser)
      |> child(:writer_callee_to_caller, %MFile.Sink{location: l2l_path})
    ]

    state = %{
      call_id: opts.call_id,
      caller_to_callee: caller_to_callee,
      callee_to_caller: callee_to_caller,
      c2c_path: c2c_path,
      l2l_path: l2l_path
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

  # SIP Call-IDs include `@`, `.`, sometimes `/` — sanitize to a filesystem-safe
  # slug, keeping the original visible enough to correlate with relay logs.
  defp sanitize_call_id(call_id) do
    String.replace(call_id, ~r/[^A-Za-z0-9_-]/, "_")
  end
end
