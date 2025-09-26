defmodule ExMedia.SDPAdapter do
  @moduledoc false
  alias ExSDP


  @type remote_sdp :: %ExSDP{} | nil


  # Parse using ex_sdp; return struct or nil
  def parse(nil), do: nil
  def parse(text) when is_binary(text) do
    try do
      case ExSDP.parse(text) do
        {:ok, sdp} -> sdp
        %ExSDP{} = sdp -> sdp
        _ -> nil
      end
    rescue
      _ -> nil
    end
  end


  # Decide payload types and direction based on remote and local policy.
  def decide_media(nil, allowed) do
    {default_pts(allowed), "sendrecv"}
  end
  def decide_media(%ExSDP{} = sdp, allowed) do
    {remote_pts, dir} = extract_remote_audio(sdp)
    pts = intersect_pts(remote_pts, allowed)
    pts = if pts == [], do: default_pts(allowed), else: pts
    {pts, dir || "sendrecv"}
  end


  # Build minimal SDP answer string
  def answer_sdp(ip, rtp_port, rtcp_port, pts, dir) do
    fmt = pts |> Enum.map(&to_string/1) |> Enum.join(" ")

    [
    "v=0",
    "o=- 0 0 IN IP4 #{ip}",
    "s=-",
    "t=0 0",
    "a=tool:ex_media",
    "m=audio #{rtp_port} RTP/AVP #{fmt}",
    "c=IN IP4 #{ip}",
    "a=rtcp:#{rtcp_port} IN IP4 #{ip}",
    "a=#{dir}",
    "a=rtcp-mux"
    ]
    |> Enum.join("\r\n")
    |> Kernel.<>("\r\n")
  end


  # -- helpers --
  defp extract_remote_audio(%ExSDP{media: media}) do
    audio = Enum.find(media, fn m -> to_string(m.type) in ["audio", ":audio"] end) || %{}
    fmt = Map.get(audio, :fmt, [])
    attributes = Map.get(audio, :attributes, [])


    dir =
      attributes
      |> Enum.map(&attr_to_string/1)
      |> Enum.find(fn s -> String.starts_with?(s, "a=") && String.replace_prefix(s, "a=", "") in ["sendrecv","sendonly","recvonly","inactive"] end)
      |> case do
            nil -> nil
            "a=" <> d -> d
            other -> other
          end


    {fmt, dir}
  end

  defp attr_to_string(t) when is_tuple(t) do
    ""
  end
  defp attr_to_string(r) do
    to_string(r)
  end

  defp intersect_pts(remote_pts, allowed) do
    rem_set = MapSet.new(Enum.map(remote_pts, &normalize_pt/1))

    allowed_set =
      cond do
        is_map(allowed) and match?(%MapSet{}, allowed) -> allowed
        is_list(allowed) -> MapSet.new(Enum.map(allowed, &normalize_pt/1))
        true -> MapSet.new()
      end

    if MapSet.size(allowed_set) == 0 do
      Enum.to_list(rem_set)
    else
      rem_set |> MapSet.intersection(allowed_set) |> Enum.to_list()
    end
  end

  defp default_pts(allowed) do
    base = [0, 101] # PCMU + telephone-event
    allowed_set =
      cond do
        is_map(allowed) and match?(%MapSet{}, allowed) -> allowed
        is_list(allowed) -> MapSet.new(Enum.map(allowed, &normalize_pt/1))
        true -> MapSet.new()
      end

    cond do
      MapSet.size(allowed_set) == 0 -> base
      true ->
        case Enum.filter(base, &MapSet.member?(allowed_set, &1)) do
          [] -> base
          xs -> xs
        end
    end
  end

  defp normalize_pt(pt) when is_integer(pt), do: pt
  defp normalize_pt(pt) when is_binary(pt) do
    case Integer.parse(pt) do
      {i, _} -> i
      _ -> pt
    end
  end

end
