defmodule RelayHandler do
  @moduledoc """
  `ExKamailio.Handler` that relays RTP between two SIP peers through a
  Membrane pipeline.

  Flow:
    * `offer/2`  — record the caller's remote endpoint; reply with the caller's
      SDP repointed at the local endpoint ex_kamailio allocated for the caller.
    * `answer/2` — both sides are known now; spawn `RelayHandler.Pipeline` and
      reply with the callee's SDP repointed at the callee-side local endpoint.
    * `delete/2` — terminate the pipeline.

  ex_kamailio keeps a separate handler state per `call_id`, so the pipeline pid
  lives directly in this call's state.
  """

  use ExKamailio.Handler

  require Logger
  alias ExKamailio.SDP

  @impl true
  def init(_opts), do: {:ok, %{pipeline: nil}}

  @impl true
  def offer(session, state) do
    Logger.info(
      "[relay] offer call=#{session.call_id} caller remote=#{inspect(session.caller_remote)} " <>
        "local=#{inspect(session.caller_local)}"
    )

    {:ok, SDP.rewrite_endpoint(session.offer_sdp, session.caller_local), state}
  end

  @impl true
  def answer(session, state) do
    Logger.info(
      "[relay] answer call=#{session.call_id} callee remote=#{inspect(session.callee_remote)} " <>
        "local=#{inspect(session.callee_local)}"
    )

    case start_pipeline(session) do
      {:ok, pid} ->
        {:ok, SDP.rewrite_endpoint(session.answer_sdp, session.callee_local),
         %{state | pipeline: pid}}

      {:error, reason} ->
        Logger.error("[relay] pipeline start failed for #{session.call_id}: #{inspect(reason)}")
        {:error, reason, state}
    end
  end

  @impl true
  def delete(session, state) do
    Logger.info("[relay] delete call=#{session.call_id}")
    stop_pipeline(state.pipeline)
    {:ok, state}
  end

  defp start_pipeline(session) do
    opts = %{
      call_id: session.call_id,
      # Bind on every interface; the address peers reach us at lives in the
      # SDP (`media_ip`), which doesn't need to be a routable IP — it can be
      # a name like `host.docker.internal` that resolves on the peer side.
      local_ip: :any,
      caller_local: session.caller_local,
      caller_remote: session.caller_remote,
      callee_local: session.callee_local,
      callee_remote: session.callee_remote
    }

    case Membrane.Pipeline.start_link(RelayHandler.Pipeline, opts) do
      {:ok, _sup, pid} -> {:ok, pid}
      other -> other
    end
  end

  defp stop_pipeline(nil), do: :ok
  defp stop_pipeline(pid), do: Membrane.Pipeline.terminate(pid, asynchronous?: true)
end
