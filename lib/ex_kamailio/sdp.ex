defmodule ExKamailio.SDP do
  @moduledoc """
  SDP parsing and rewriting helpers.

  Thin wrapper over `ExSDP`. Handlers typically call `rewrite_endpoint/2`
  to forward a peer's SDP repointed at their allocated media address
  (preserving the offered codecs).
  """

  alias ExKamailio.Endpoint

  @doc """
  Parse a textual SDP body. Returns the `%ExSDP{}` struct on success.
  """
  @spec parse(String.t() | nil) :: {:ok, ExSDP.t()} | {:error, term()}
  def parse(nil), do: {:error, :no_sdp}

  def parse(text) when is_binary(text) do
    try do
      case ExSDP.parse(text) do
        {:ok, sdp} -> {:ok, sdp}
        {:error, error} -> {:error, error}
      end
    rescue
      error -> {:error, error}
    end
  end

  @doc """
  Repoint a parsed SDP at a local endpoint, preserving its codecs.

  Returns a copy of `sdp` with the session origin/connection address and the
  first audio media's port (and `c=`/`a=rtcp:`) rewritten to advertise `local`.
  Everything else — the offered payload types, `rtpmap`/`fmtp`, direction — is
  left untouched, so the answer carries exactly the codecs the peer offered.

  This is the forwarder primitive: `ex_kamailio` doesn't decide codecs, it
  forwards the peer's SDP after pointing the media at your relay address.
  """
  @spec rewrite_endpoint(ExSDP.t(), Endpoint.t()) :: ExSDP.t()
  def rewrite_endpoint(%ExSDP{} = sdp, %Endpoint{} = local) do
    addr = to_sdp_address(local.ip)
    conn = %ExSDP.ConnectionData{address: addr}
    rtcp_port = local.rtcp_port || local.rtp_port + 1

    media =
      Enum.map(sdp.media, fn
        %ExSDP.Media{type: type} = m when type in [:audio, "audio"] ->
          attrs =
            m.attributes
            |> Enum.reject(&match?({"rtcp", _}, &1))
            |> List.insert_at(0, {"rtcp", rtcp_line(rtcp_port, addr)})

          %{m | port: local.rtp_port, connection_data: [conn], attributes: attrs}

        other ->
          other
      end)

    %{sdp | connection_data: conn, origin: %{sdp.origin | address: addr}, media: media}
  end

  defp rtcp_line(port, addr),
    do: "#{port} IN #{ExSDP.Address.get_addrtype(addr)} #{ExSDP.Address.serialize_address(addr)}"

  defp to_sdp_address(ip) when is_tuple(ip), do: ip

  defp to_sdp_address(ip) when is_binary(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, tuple} -> tuple
      {:error, _} -> {:IP4, ip}
    end
  end

  @doc """
  Extract the first audio media endpoint (IP + port) from a parsed
  SDP. Returns `nil` if the SDP has no audio media or no connection
  data.
  """
  @spec first_audio_endpoint(ExSDP.t()) :: Endpoint.t() | nil
  def first_audio_endpoint(%ExSDP{media: media}) do
    Enum.find_value(media, fn
      %ExSDP.Media{type: type, port: port, connection_data: cd} when type in [:audio, "audio"] ->
        build_endpoint(port, cd)

      _ ->
        nil
    end)
  end

  defp build_endpoint(port, %ExSDP.ConnectionData{address: ip}),
    do: %Endpoint{ip: ip, rtp_port: port}

  defp build_endpoint(port, [%ExSDP.ConnectionData{address: ip} | _]),
    do: %Endpoint{ip: ip, rtp_port: port}

  defp build_endpoint(_port, _), do: nil
end
