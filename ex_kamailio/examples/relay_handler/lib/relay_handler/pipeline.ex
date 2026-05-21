defmodule RelayHandler.Pipeline do
  @moduledoc """
  A minimal two-peer RTP relay built from a pair of `Membrane.UDP.Endpoint`s
  wired crosswise.

      caller peer  <->  :leg_caller (UDP)  <->  :leg_callee (UDP)  <->  callee peer

  Each leg binds to a local port allocated by ex_kamailio (where its peer's RTP
  arrives) and sends out to that peer's SDP-advertised address. Output buffers
  from one leg feed straight into the input of the other.

  Limitations:
    * RTP only — RTCP is not relayed (would need a second pair of endpoints).
    * No latching — destinations come from the SDP and are fixed for the call.
      If a peer is behind symmetric NAT, this won't work; latching can be added
      by inspecting `udp_source_address`/`udp_source_port` metadata on output
      buffers and rewriting the opposite leg's destination.
  """

  use Membrane.Pipeline

  require Membrane.Logger
  alias Membrane.UDP.Endpoint
  alias ExKamailio.Endpoint, as: EkEndpoint

  @type opts :: %{
          call_id: String.t(),
          local_ip: :inet.ip_address(),
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

    caller_leg = %Endpoint{
      local_address: opts.local_ip,
      local_port_no: opts.caller_local.rtp_port,
      destination_address: opts.caller_remote.ip,
      destination_port_no: opts.caller_remote.rtp_port
    }

    callee_leg = %Endpoint{
      local_address: opts.local_ip,
      local_port_no: opts.callee_local.rtp_port,
      destination_address: opts.callee_remote.ip,
      destination_port_no: opts.callee_remote.rtp_port
    }

    spec = [
      child(:leg_caller, caller_leg) |> child(:leg_callee, callee_leg),
      get_child(:leg_callee) |> get_child(:leg_caller)
    ]

    {[spec: spec], %{call_id: opts.call_id}}
  end
end
