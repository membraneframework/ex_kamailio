defmodule EchoHandler do
  @moduledoc """
  A trivial `ExKamailio.Handler` that logs the SDPs it receives and
  answers with a bare-minimum sendrecv SDP pointing at the local
  endpoint ex_kamailio has just allocated.

  Replace `offer/2` and `answer/2` with calls into your media pipeline
  (Membrane, FFmpeg, etc.) to do something more interesting.
  """

  use ExKamailio.Handler

  require Logger
  alias ExKamailio.SDP

  @impl true
  def offer(session, state) do
    Logger.info(
      "[echo] offer call=#{session.call_id} remote=#{inspect(session.caller_remote)} local=#{inspect(session.caller_local)}"
    )

    {:ok, SDP.rewrite_endpoint(session.offer_sdp, session.caller_local), state}
  end

  @impl true
  def answer(session, state) do
    Logger.info(
      "[echo] answer call=#{session.call_id} remote=#{inspect(session.callee_remote)} local=#{inspect(session.callee_local)}"
    )

    {:ok, SDP.rewrite_endpoint(session.answer_sdp, session.callee_local), state}
  end

  @impl true
  def delete(session, state) do
    Logger.info("[echo] delete call=#{session.call_id}")
    {:ok, state}
  end
end
