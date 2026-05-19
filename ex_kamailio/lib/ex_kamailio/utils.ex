defmodule ExKamailio.Utils do
  @moduledoc false

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
