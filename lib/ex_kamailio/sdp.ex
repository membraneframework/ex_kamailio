defmodule ExKamailio.SDP do
  @moduledoc """
  SDP parsing and answer-building helpers.

  Thin wrapper over `ExSDP`. Handlers typically call `rewrite_endpoint/2`
  to forward a peer's SDP repointed at their allocated media address
  (preserving the offered codecs); `answer_sdp/5` builds a minimal answer
  from scratch instead (e.g. to force a single codec like PCMU).
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
  Decide which audio payload types and direction to advertise in the
  answer, given the remote SDP and a `MapSet` of locally-allowed PTs.

  Falls back to PCMU (0) and `telephone-event` (101) if there is no
  intersection between remote-offered and locally-allowed PTs.
  """
  @spec decide_media(ExSDP.t() | nil, MapSet.t() | [integer()]) :: {[integer()], String.t()}
  def decide_media(nil, allowed), do: {default_pts(allowed), "sendrecv"}

  def decide_media(%ExSDP{} = sdp, allowed) do
    {remote_pts, dir} = extract_remote_audio(sdp)
    allowed_set = to_pt_set(allowed)

    pts =
      case intersect_pts(remote_pts, allowed_set) do
        [] -> default_pts(allowed_set)
        xs -> xs
      end

    {pts, dir || "sendrecv"}
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
  Build a minimal SDP answer string advertising the given local
  endpoint, payload types, and direction.
  """
  @spec answer_sdp(String.t(), pos_integer(), pos_integer(), [integer()], String.t()) ::
          String.t()
  def answer_sdp(ip, rtp_port, rtcp_port, pts, dir) do
    fmt = pts |> Enum.map(&to_string/1) |> Enum.join(" ")

    [
      "v=0",
      "o=- 0 0 IN IP4 #{ip}",
      "s=-",
      "t=0 0",
      "a=tool:ex_kamailio",
      "m=audio #{rtp_port} RTP/AVP #{fmt}",
      "c=IN IP4 #{ip}",
      "a=rtcp:#{rtcp_port} IN IP4 #{ip}",
      "a=#{dir}",
      "a=rtcp-mux"
    ]
    |> Enum.join("\r\n")
    |> Kernel.<>("\r\n")
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

  defp extract_remote_audio(%ExSDP{media: media}) do
    audio = Enum.find(media, fn m -> to_string(m.type) in ["audio", ":audio"] end) || %{}
    fmt = Map.get(audio, :fmt, [])
    attributes = Map.get(audio, :attributes, [])

    dir =
      attributes
      |> Enum.map(&attr_to_string/1)
      |> Enum.find(fn s ->
        String.starts_with?(s, "a=") and
          String.replace_prefix(s, "a=", "") in [
            "sendrecv",
            "sendonly",
            "recvonly",
            "inactive"
          ]
      end)
      |> case do
        nil -> nil
        "a=" <> d -> d
        other -> other
      end

    {fmt, dir}
  end

  defp attr_to_string(t) when is_tuple(t), do: ""
  defp attr_to_string(r), do: to_string(r)

  defp intersect_pts(remote_pts, allowed_set) do
    remote_set = MapSet.new(Enum.map(remote_pts, &normalize_pt/1))

    if MapSet.size(allowed_set) == 0,
      do: Enum.to_list(remote_set),
      else: remote_set |> MapSet.intersection(allowed_set) |> Enum.to_list()
  end

  defp default_pts(allowed) do
    allowed_set = to_pt_set(allowed)
    base = [0, 101]

    cond do
      MapSet.size(allowed_set) == 0 ->
        base

      true ->
        Enum.filter(base, &MapSet.member?(allowed_set, &1))
        |> case do
          [] -> base
          xs -> xs
        end
    end
  end

  defp to_pt_set(%MapSet{} = set), do: set
  defp to_pt_set(list) when is_list(list), do: MapSet.new(Enum.map(list, &normalize_pt/1))
  defp to_pt_set(_), do: MapSet.new()

  defp normalize_pt(pt) when is_integer(pt), do: pt

  defp normalize_pt(pt) when is_binary(pt) do
    case Integer.parse(pt) do
      {i, _} -> i
      _ -> pt
    end
  end
end
