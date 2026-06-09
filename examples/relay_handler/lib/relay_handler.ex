defmodule RelayHandler do
  @moduledoc """
  `ExKamailio.Handler` that relays RTP between two SIP peers through a
  Membrane pipeline.

  ex_kamailio is a pure SDP shuttle: it owns no media ports and picks no
  codecs. This handler is what binds sockets, picks ports and runs the media —
  and it builds the relay one leg at a time, in step with the dialog:

    * `offer/2`  — pick the local port the *callee* will send to, start the
      pipeline with the callee→caller leg (bound to that port, forwarding to
      the caller), and advertise it in the reply SDP.
    * `answer/2` — pick the local port the *caller* will send to, add the
      caller→callee leg to the running pipeline, and advertise it.
    * `delete/2` — terminate the pipeline.

  ex_kamailio keeps a separate handler state per `call_id`, so the pipeline pid
  lives directly in this call's state.
  """

  use ExKamailio.Handler

  require Logger
  alias ExKamailio.{Endpoint, SDP, Utils}
  alias RelayHandler.PortPool

  @impl true
  def init(_opts) do
    media_ip = Utils.resolve_media_ip(Application.get_env(:relay_handler, :media_ip, "auto"))
    {:ok, %{media_ip: media_ip, pipeline: nil, caller_local: nil, callee_local: nil}}
  end

  @impl true
  def offer(session, state) do
    # The port we advertise here goes into the rewritten INVITE — it's the port
    # the *callee* will send to. Stand up the callee→caller leg now: it listens
    # on that port and forwards to the caller (known from the offer SDP). No
    # media flows until the callee answers, but the socket is bound from now on.
    local = checkout(state.media_ip, {session.call_id, :caller})

    Logger.info(
      "[relay] offer call=#{session.call_id} caller remote=#{inspect(session.caller_remote)} " <>
        "advertising local=#{inspect(local)}"
    )

    case start_pipeline(session.call_id, local.rtp_port, session.caller_remote) do
      {:ok, pid} ->
        {:ok, pcmu_sdp(local), %{state | pipeline: pid, caller_local: local}}

      {:error, reason} ->
        Logger.error("[relay] pipeline start failed for #{session.call_id}: #{inspect(reason)}")
        PortPool.release({session.call_id, :caller}, local.rtp_port)
        {:error, reason, state}
    end
  end

  @impl true
  def answer(session, state) do
    # This port goes back to the caller in 200 OK — the port the *caller* sends
    # to. Add the caller→callee leg: listen on it, forward to the callee.
    local = checkout(state.media_ip, {session.call_id, :callee})

    Logger.info(
      "[relay] answer call=#{session.call_id} callee remote=#{inspect(session.callee_remote)} " <>
        "advertising local=#{inspect(local)}"
    )

    send(state.pipeline, {:add_leg, local.rtp_port, session.callee_remote})
    {:ok, pcmu_sdp(local), %{state | callee_local: local}}
  end

  @impl true
  def delete(session, state) do
    Logger.info("[relay] delete call=#{session.call_id}")
    stop_pipeline(state.pipeline)
    release(state.caller_local, {session.call_id, :caller})
    release(state.callee_local, {session.call_id, :callee})
    {:ok, state}
  end

  # Force PCMU (G.711 μ-law) on both legs instead of forwarding the peers'
  # codecs, so the per-call `.wav` recordings decode cleanly. ex_kamailio stays
  # codec-agnostic — this is the handler's choice. Swap in
  # `SDP.rewrite_endpoint(peer_sdp, local)` to forward the negotiated codecs
  # (Opus, etc.) instead.
  defp pcmu_sdp(local) do
    SDP.answer_sdp(local.ip, local.rtp_port, local.rtcp_port, [0, 101], "sendrecv")
  end

  # The handler owns its media ports. ex_kamailio no longer allocates them, so
  # the example keeps its own pool (`RelayHandler.PortPool`).
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
end
