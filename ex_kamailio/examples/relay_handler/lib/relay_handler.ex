defmodule RelayHandler do
  @moduledoc """
  `ExKamailio.Handler` that relays RTP between two SIP peers through a
  Membrane pipeline.

  Flow:
    * `offer/2`  — record the caller's remote endpoint; reply with the local
      endpoint ex_kamailio just allocated for the caller side.
    * `answer/2` — both sides are known now; spawn `RelayHandler.Pipeline`
      and reply with the local endpoint allocated for the callee side.
    * `delete/2` — terminate the pipeline.

  Pipelines are tracked in `RelayHandler.PipelineRegistry` keyed by `call_id`.
  """

  @behaviour ExKamailio.Handler

  require Logger
  alias ExKamailio.{Endpoint, SDP}

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def offer(session, state) do
    Logger.info(
      "[relay] offer call=#{session.call_id} caller remote=#{inspect(session.caller_remote)} " <>
        "local=#{inspect(session.caller_local)}"
    )

    {:ok, answer_for(session.caller_local), state}
  end

  @impl true
  def answer(session, state) do
    Logger.info(
      "[relay] answer call=#{session.call_id} callee remote=#{inspect(session.callee_remote)} " <>
        "local=#{inspect(session.callee_local)}"
    )

    case start_pipeline(session) do
      {:ok, _pid} ->
        {:ok, answer_for(session.callee_local), state}

      {:error, reason} ->
        Logger.error("[relay] pipeline start failed for #{session.call_id}: #{inspect(reason)}")
        {:error, reason, state}
    end
  end

  @impl true
  def delete(session, state) do
    Logger.info("[relay] delete call=#{session.call_id}")
    stop_pipeline(session.call_id)
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
      {:ok, _sup, pid} ->
        Registry.register(RelayHandler.PipelineRegistry, session.call_id, pid)
        {:ok, pid}

      other ->
        other
    end
  end

  defp stop_pipeline(call_id) do
    case Registry.lookup(RelayHandler.PipelineRegistry, call_id) do
      [{_owner, pid}] ->
        Registry.unregister(RelayHandler.PipelineRegistry, call_id)
        Membrane.Pipeline.terminate(pid, asynchronous?: true)

      [] ->
        :ok
    end
  end

  defp answer_for(%Endpoint{ip: ip, rtp_port: rtp, rtcp_port: rtcp}) do
    SDP.answer_sdp(ip_to_string(ip), rtp, rtcp || rtp + 1, [0, 101], "sendrecv")
  end

  defp ip_to_string(ip) when is_tuple(ip), do: :inet.ntoa(ip) |> to_string()
  defp ip_to_string(ip) when is_binary(ip), do: ip
end
