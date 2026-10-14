defmodule ExKamailio.CallHandler.Default do
  @moduledoc """
  Passthrough handler used when no `:call_handler` is configured.

  It returns each peer's SDP unchanged, so ex_kamailio allocates no media and
  the two endpoints negotiate directly. This keeps the app functional out of the
  box (and when pulled in as a transitive dependency); configure your own
  `ExKamailio.CallHandler` to actually handle the media.
  """
  use ExKamailio.CallHandler

  @impl true
  def init(_session, _opts), do: {:ok, %{}}

  @impl true
  def handle_offer(from_offerer_sdp, _session, state), do: {:ok, from_offerer_sdp, state}

  @impl true
  def handle_answer(from_answerer_sdp, _session, state), do: {:ok, from_answerer_sdp, state}
end
