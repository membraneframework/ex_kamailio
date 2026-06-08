defmodule ExKamailio.Utils do
  @moduledoc """
  Small networking helpers used across `ex_kamailio` and handy in handlers.
  """

  require Logger

  @doc """
  Best-effort discovery of this host's first non-loopback IPv4 address,
  formatted as a string suitable for SDP `c=` lines. Falls back to
  `"127.0.0.1"` if no non-loopback address is found.

  Pairs with `config :ex_kamailio, media_ip: :auto`, which resolves the
  advertised media IP through this function at connection start. On a
  multi-homed host the first matching interface wins.
  """
  @spec detect_media_ip() :: String.t()
  def detect_media_ip do
    {:ok, ifs} = :inet.getifaddrs()

    ifs
    |> Enum.flat_map(fn {_name, opts} -> Keyword.get_values(opts, :addr) end)
    |> Enum.find(fn
      {127, _, _, _} -> false
      {_, _, _, _} -> true
      _ -> false
    end)
    |> case do
      nil -> "127.0.0.1"
      ip -> ip_to_string(ip)
    end
  end

  @doc """
  Resolve a configured `media_ip` value. `:auto` (or `"auto"`) triggers
  `detect_media_ip/0`; any other value is used verbatim.
  """
  @spec resolve_media_ip(:auto | String.t() | :inet.ip_address()) :: String.t() | :inet.ip_address()
  def resolve_media_ip(media_ip) when media_ip in [:auto, "auto"] do
    ip = detect_media_ip()
    Logger.info("media_ip: :auto resolved to #{ip}")
    ip
  end

  def resolve_media_ip(media_ip), do: media_ip

  @doc """
  Parse a textual IP address into Erlang's `:inet.ip_address()` tuple.

  Raises if the address is malformed.
  """
  @spec parse_ip!(String.t() | :inet.ip_address()) :: :inet.ip_address()
  def parse_ip!(ip) when is_tuple(ip), do: ip

  def parse_ip!(string) when is_binary(string) do
    case :inet.parse_address(String.to_charlist(string)) do
      {:ok, ip} -> ip
      {:error, reason} -> raise ArgumentError, "invalid IP #{inspect(string)}: #{inspect(reason)}"
    end
  end

  @doc "Format an IP (tuple or string) as a string suitable for SDP `c=` lines."
  @spec ip_to_string(:inet.ip_address() | String.t()) :: String.t()
  def ip_to_string(ip) when is_binary(ip), do: ip
  def ip_to_string(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string()
end
