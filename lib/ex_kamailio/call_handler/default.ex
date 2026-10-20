defmodule ExKamailio.CallHandler.Default do
  @moduledoc """
  Passthrough used when `:call_handler` config field is not set. It returns each peer's SDP
  unchanged, so the peers send media straight to each other and an app that
  pulls ex_kamailio in without configuring it, e.g. as a transitive
  dependency, still routes calls. Set `:call_handler` config field to handle the media
  yourself. Take a look at `README.md` for more information.
  """
  use ExKamailio.CallHandler

  @impl true
  def init(_session, _opts), do: {:ok, %{}}

  @impl true
  def handle_offer(from_offerer_sdp, _session, state), do: {:ok, from_offerer_sdp, state}

  @impl true
  def handle_answer(from_answerer_sdp, _session, state), do: {:ok, from_answerer_sdp, state}
end
