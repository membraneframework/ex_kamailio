defmodule ExKamailio.CallHandler.Default do
  @moduledoc """
  Passthrough used when `:call_handler` is not set: each peer's SDP goes back
  unchanged, so the peers send media straight to each other. It keeps an app
  that pulls ex_kamailio in without configuring it, e.g. as a transitive
  dependency, working; set `:call_handler` to handle the media yourself.
  """
  use ExKamailio.CallHandler

  @impl true
  def init(_session, _opts), do: {:ok, %{}}

  @impl true
  def handle_offer(from_offerer_sdp, _session, state), do: {:ok, from_offerer_sdp, state}

  @impl true
  def handle_answer(from_answerer_sdp, _session, state), do: {:ok, from_answerer_sdp, state}
end
