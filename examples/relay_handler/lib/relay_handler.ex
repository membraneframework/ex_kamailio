defmodule RelayHandler do
  @moduledoc """
  `ExKamailio.CallHandler` that relays RTP between the two peers of a call
  through a Membrane pipeline.

  ex_kamailio only passes SDP between Kamailio and this module; the media is
  the handler's business. Every call gets its own `RelayHandler.Pipeline` with
  one UDP socket per peer, and each peer's SDP is rewritten so that the other
  peer sends its RTP to the relay.
  """

  use ExKamailio.CallHandler

  alias ExSDP.ConnectionData
  alias RelayHandler.Pipeline

  @impl true
  def init(session, _opts) do
    {:ok, _supervisor, pipeline} = Membrane.Pipeline.start_link(Pipeline, session.call_id)
    {:ok, %{pipeline: pipeline, ports: nil}}
  end

  @impl true
  def handle_offer(offer, _session, state) do
    ports = Membrane.Pipeline.call(state.pipeline, {:offer, media_address(offer)})
    {:ok, relayed(offer, ports.answerer), %{state | ports: ports}}
  end

  @impl true
  def handle_answer(answer, _session, state) do
    :ok = Membrane.Pipeline.call(state.pipeline, {:answer, media_address(answer)})
    {:ok, relayed(answer, state.ports.offerer), state}
  end

  @impl true
  def handle_delete(_session, state) do
    :ok = Membrane.Pipeline.terminate(state.pipeline)
  end

  # Where the peer wants its audio sent.
  defp media_address(sdp) do
    media = audio(sdp)
    %ConnectionData{address: ip} = media.connection_data || sdp.connection_data
    {ip, media.port}
  end

  # The peer's SDP with the relay as the media address. Anything but the first
  # audio stream is rejected (port 0); RTCP shares the RTP socket.
  defp relayed(sdp, port) do
    relay = %ConnectionData{address: Application.fetch_env!(:relay_handler, :media_ip)}
    audio = audio(sdp)

    media =
      Enum.map(sdp.media, fn
        ^audio ->
          attributes = Enum.reject(audio.attributes, &match?({"rtcp", _}, &1))

          %{
            audio
            | port: port,
              connection_data: relay,
              attributes: Enum.uniq([:rtcp_mux | attributes])
          }

        other ->
          %{other | port: 0}
      end)

    %{sdp | connection_data: relay, media: media}
  end

  defp audio(sdp), do: Enum.find(sdp.media, &(&1.type == :audio))
end
