defmodule RelayHandler.Pipeline do
  @moduledoc """
  Per-call RTP relay, built one leg at a time as the SIP dialog progresses.

  ex_kamailio is a pure SDP shuttle — it allocates no ports and owns no media.
  This pipeline (and the ports it binds) is entirely the handler's
  responsibility, and it grows with the call:

    * On `offer`, `RelayHandler` starts this pipeline with the **callee→caller**
      leg: a `Membrane.UDP.Source` bound to the local port advertised to the
      callee, forwarding to the caller's SDP address. No media flows yet — the
      callee hasn't answered — but the socket is bound, so the advertised port
      is real.
    * On `answer`, the handler sends `{:add_leg, port, dest}` and the
      **caller→callee** leg is added: a source bound to the port advertised to
      the caller, forwarding to the callee's SDP address.

  Each leg fans its inbound RTP out through a `Tee.Parallel`: one branch
  forwards to the far party (`UDP.Sink`); the other decodes the μ-law payload
  and writes a playable `/recordings/<call_id>__<direction>.wav` — proof, on
  disk, that the bytes flowed through Membrane.

  `RelayHandler` forces PCMU (G.711 μ-law, PT 0), so recordings are μ-law,
  8 kHz, mono; the record branch decodes to PCM via `Membrane.G711.FFmpeg`
  (the pure-Elixir `membrane_g711_plugin` only does A-law) and serializes a WAV
  header, so the files play directly:

      ffplay <call_id>__caller_to_callee.wav

  Limitations:
    * RTP only — RTCP is not relayed.
    * No symmetric-RTP latching: each leg sends to the address from the peer's
      SDP. Fine on a routable network; a NAT'd peer would need latching, which
      belongs to a bidirectional leg.
  """

  use Membrane.Pipeline

  require Membrane.Logger
  alias Membrane.{Debug, RTP, Tee, UDP, WAV}
  alias Membrane.G711.FFmpeg.Decoder, as: G711Decoder
  alias Membrane.RTP.G711.Depayloader, as: G711Depayloader
  alias Membrane.File, as: MFile
  alias ExKamailio.Endpoint, as: EkEndpoint

  @type opts :: %{
          call_id: String.t(),
          local_ip: :inet.socket_address(),
          listen_port: :inet.port_number(),
          send_to: EkEndpoint.t()
        }

  @impl true
  def handle_init(_ctx, opts) do
    recordings_dir = Application.get_env(:relay_handler, :recordings_dir, "recordings")
    File.mkdir_p!(recordings_dir)
    safe_id = sanitize_call_id(opts.call_id)

    state = %{
      call_id: opts.call_id,
      local_ip: opts.local_ip,
      safe_id: safe_id,
      recordings_dir: recordings_dir,
      counters: %{
        caller_to_callee: :counters.new(1, []),
        callee_to_caller: :counters.new(1, [])
      }
    }

    Membrane.Logger.info(
      "[relay] start call=#{opts.call_id} callee→caller leg: " <>
        "listen :#{opts.listen_port} -> #{inspect(opts.send_to)}"
    )

    spec = leg(:callee_to_caller, state, opts.listen_port, opts.send_to)
    {[spec: spec, start_timer: {:tally, Membrane.Time.second()}], state}
  end

  @impl true
  def handle_info({:add_leg, listen_port, send_to}, _ctx, state) do
    Membrane.Logger.info(
      "[relay] call=#{state.call_id} caller→callee leg: " <>
        "listen :#{listen_port} -> #{inspect(send_to)}"
    )

    spec = leg(:caller_to_callee, state, listen_port, send_to)
    {[spec: spec], state}
  end

  @impl true
  def handle_tick(:tally, _ctx, state) do
    a = :counters.get(state.counters.caller_to_callee, 1)
    b = :counters.get(state.counters.callee_to_caller, 1)

    Membrane.Logger.info(
      "[relay] call=#{state.call_id} caller→callee=#{a} pkts, callee→caller=#{b} pkts"
    )

    {[], state}
  end

  # One unidirectional leg: receive RTP on `listen_port`, fan out to a UDP sink
  # toward `dest` and to a WAV recorder. `dir` names both the recording file and
  # the packet counter, and keeps the per-leg child names unique.
  defp leg(dir, state, listen_port, %EkEndpoint{} = dest) do
    wav = Path.join(state.recordings_dir, "#{state.safe_id}__#{dir}.wav")
    counter = Map.fetch!(state.counters, dir)

    [
      child({:src, dir}, %UDP.Source{local_address: state.local_ip, local_port_no: listen_port})
      |> child({:tee, dir}, Tee.Parallel),
      get_child({:tee, dir})
      |> child({:probe, dir}, %Debug.Filter{handle_buffer: tally(counter)})
      |> child(
        {:sink, dir},
        %UDP.Sink{destination_address: dest.ip, destination_port_no: dest.rtp_port}
      ),
      get_child({:tee, dir})
      |> child({:parser, dir}, RTP.Parser)
      |> child({:depay, dir}, G711Depayloader)
      |> child({:decoder, dir}, %G711Decoder{encoding: :PCMU})
      |> child({:wav, dir}, WAV.Serializer)
      |> child({:writer, dir}, %MFile.Sink{location: wav})
    ]
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
