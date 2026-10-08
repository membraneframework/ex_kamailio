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

  alias ExSDP.Attribute.{FMTP, RTPMapping}
  alias ExSDP.ConnectionData
  alias RelayHandler.Pipeline

  # Only PCMA gets through, so every recording is A-law. The handler's choice;
  # ex_kamailio itself is codec-agnostic.
  @codec "PCMA"

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

  # Where the peer wants its audio sent. ExSDP gives the m-line the session's
  # c= line when it has none of its own, as a struct rather than a list.
  defp media_address(sdp) do
    media = audio(sdp)
    [%ConnectionData{address: ip} | _] = List.wrap(media.connection_data)
    {ip, media.port}
  end

  # The peer's SDP with the relay as the media address. Anything but the first
  # audio stream is rejected (port 0); RTCP shares the RTP socket.
  defp relayed(sdp, port) do
    relay = %ConnectionData{address: Application.fetch_env!(:relay_handler, :media_ip)}
    audio = audio(sdp)

    media =
      Enum.map(sdp.media, fn
        ^audio -> relayed_audio(audio, relay, port)
        other -> %{other | port: 0}
      end)

    %{
      sdp
      | connection_data: relay,
        media: media,
        attributes: Enum.reject(sdp.attributes, &transport_attribute?/1)
    }
  end

  defp relayed_audio(audio, connection, port) do
    payload_types = payload_types(audio)

    attributes =
      Enum.reject(audio.attributes, fn
        %RTPMapping{payload_type: pt} -> pt not in payload_types
        %FMTP{pt: pt} -> pt not in payload_types
        attribute -> transport_attribute?(attribute)
      end)

    %{
      audio
      | port: port,
        connection_data: connection,
        fmt: Enum.filter(audio.fmt, &(&1 in payload_types)),
        attributes: Enum.uniq([:rtcp_mux | attributes])
    }
  end

  # PCMA is static payload type 8 and may come without an rtpmap line.
  defp payload_types(audio) do
    mapped =
      for %RTPMapping{payload_type: pt, encoding: encoding} <- audio.attributes,
          String.upcase(encoding) == @codec,
          do: pt

    [8 | mapped]
  end

  defp audio(sdp), do: Enum.find(sdp.media, &(&1.type == :audio))

  # Where media goes is the relay's to say, so the peer's RTCP address and ICE
  # candidates go; direction, keys and the rest stay the peer's.
  defp transport_attribute?({key, _}),
    do: key in ["rtcp", "candidate", :ice_ufrag, :ice_pwd, :ice_options]

  defp transport_attribute?(attribute), do: attribute in ["end-of-candidates", :ice_lite]
end
