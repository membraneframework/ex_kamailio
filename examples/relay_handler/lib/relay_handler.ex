defmodule RelayHandler do
  @moduledoc """
  `ExKamailio.CallHandler` that relays RTP between two SIP peers through a
  Membrane pipeline.

  ex_kamailio is a pure SDP shuttle: it owns no media ports and picks no
  codecs. This handler is what binds sockets, picks ports and runs the media —
  and it builds the relay one leg at a time, in step with the dialog:

    * `handle_offer/3`  — pick the local port the *answerer* will send to, start
      the pipeline with the answerer→offerer leg (bound to that port, forwarding
      to the offerer), and advertise it in the reply SDP.
    * `handle_answer/3` — pick the local port the *offerer* will send to, add
      the offerer→answerer leg to the running pipeline, and advertise it.
    * `handle_delete/2` — terminate the pipeline.

  ex_kamailio keeps a separate handler state per `call_id`, so the pipeline pid
  lives directly in this call's state.
  """

  use ExKamailio.CallHandler

  require Logger
  alias ExKamailio.Endpoint
  alias RelayHandler.PortPool

  @impl true
  def init(_opts) do
    media_ip = resolve_media_ip(Application.get_env(:relay_handler, :media_ip, "auto"))
    {:ok, %{media_ip: media_ip, pipeline: nil, offerer_local: nil, answerer_local: nil}}
  end

  @impl true
  def handle_offer(offer, session, state) do
    # This port goes into the rewritten INVITE — the port the *answerer* sends
    # to. Start the answerer→offerer leg now; media flows once the peer answers.
    remote = remote_endpoint(offer)
    local = checkout(state.media_ip, {session.call_id, :offerer})

    Logger.info(
      "[relay] offer call=#{session.call_id} offerer remote=#{inspect(remote)} " <>
        "advertising local=#{inspect(local)}"
    )

    case start_pipeline(session.call_id, local.rtp_port, remote) do
      {:ok, pid} ->
        {:ok, pcmu_sdp(local), %{state | pipeline: pid, offerer_local: local}}

      {:error, reason} ->
        PortPool.release({session.call_id, :offerer}, local.rtp_port)
        raise "pipeline start failed for #{session.call_id}: #{inspect(reason)}"
    end
  end

  @impl true
  def handle_answer(answer, session, state) do
    # This port goes back to the offerer in 200 OK — the port the *offerer*
    # sends to. Add the offerer→answerer leg: listen on it, forward onwards.
    remote = remote_endpoint(answer)
    local = checkout(state.media_ip, {session.call_id, :answerer})

    Logger.info(
      "[relay] answer call=#{session.call_id} answerer remote=#{inspect(remote)} " <>
        "advertising local=#{inspect(local)}"
    )

    send(state.pipeline, {:add_leg, local.rtp_port, remote})
    {:ok, pcmu_sdp(local), %{state | answerer_local: local}}
  end

  @impl true
  def handle_delete(session, state) do
    Logger.info("[relay] delete call=#{session.call_id}")
    stop_pipeline(state.pipeline)
    release(state.offerer_local, {session.call_id, :offerer})
    release(state.answerer_local, {session.call_id, :answerer})
    {:ok, state}
  end

  # Force PCMU on both legs so the per-call `.wav` recordings decode cleanly —
  # the handler's choice, ex_kamailio stays codec-agnostic. Swap in
  # `ExKamailio.SDP.rewrite_endpoint(peer_sdp, local)` to forward the codecs.
  defp pcmu_sdp(local) do
    [
      "v=0",
      "o=- 0 0 IN IP4 #{local.ip}",
      "s=-",
      "t=0 0",
      "a=tool:relay_handler",
      "m=audio #{local.rtp_port} RTP/AVP 0 101",
      "c=IN IP4 #{local.ip}",
      "a=rtcp:#{local.rtcp_port} IN IP4 #{local.ip}",
      "a=sendrecv",
      "a=rtcp-mux"
    ]
    |> Enum.join("\r\n")
    |> Kernel.<>("\r\n")
    |> ExSDP.parse!()
  end

  # Where to send RTP: address + port of the first live audio m-line.
  defp remote_endpoint(sdp) do
    media = Enum.find(sdp.media, &(&1.type == :audio and &1.port > 0))
    [%ExSDP.ConnectionData{address: ip} | _] = List.wrap(media.connection_data)
    %Endpoint{ip: ip, rtp_port: media.port}
  end

  defp checkout(media_ip, key) do
    {:ok, {rtp, _}} = PortPool.checkout(key)
    %Endpoint{ip: media_ip, rtp_port: rtp, rtcp_port: rtp + 1}
  end

  defp release(nil, _key), do: :ok
  defp release(%Endpoint{rtp_port: rtp}, key), do: PortPool.release(key, rtp)

  defp start_pipeline(call_id, listen_port, send_to) do
    opts = %{
      call_id: call_id,
      # Bind on every interface; the address peers reach us at lives in the SDP
      # (`media_ip`), which doesn't need to be the bind address.
      local_ip: :any,
      listen_port: listen_port,
      send_to: send_to
    }

    case Membrane.Pipeline.start_link(RelayHandler.Pipeline, opts) do
      {:ok, _sup, pid} -> {:ok, pid}
      other -> other
    end
  end

  defp stop_pipeline(nil), do: :ok
  defp stop_pipeline(pid), do: Membrane.Pipeline.terminate(pid, asynchronous?: true)

  # "auto" advertises this host's first non-loopback IPv4 in the SDP.
  defp resolve_media_ip(media_ip) when media_ip in [:auto, "auto"] do
    {:ok, ifs} = :inet.getifaddrs()

    ip =
      ifs
      |> Enum.flat_map(fn {_name, opts} -> Keyword.get_values(opts, :addr) end)
      |> Enum.find({127, 0, 0, 1}, fn
        {127, _, _, _} -> false
        {_, _, _, _} -> true
        _ -> false
      end)
      |> :inet.ntoa()
      |> to_string()

    Logger.info("media_ip: :auto resolved to #{ip}")
    ip
  end

  defp resolve_media_ip(media_ip), do: media_ip
end
