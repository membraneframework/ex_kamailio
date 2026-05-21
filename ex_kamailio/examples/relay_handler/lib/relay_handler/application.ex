defmodule RelayHandler.Application do
  @moduledoc false
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    maybe_override_media_ip()

    Supervisor.start_link(
      [{Registry, keys: :unique, name: RelayHandler.PipelineRegistry}],
      strategy: :one_for_one,
      name: RelayHandler.Supervisor
    )
  end

  # In dockerized mode the operator can set `MEDIA_IP=auto` (or leave the env
  # value as a hostname like `relay`) and the app will discover its own first
  # non-loopback IPv4 and use that in SDP answers. SIPp / Kamailio's
  # rtpengine_offer expect an IP literal in `c=IN IP4 ...`, not an FQDN.
  defp maybe_override_media_ip do
    case Application.fetch_env!(:ex_kamailio, :media_ip) do
      "auto" ->
        Application.put_env(:ex_kamailio, :media_ip, discover_ip())

      ip when is_binary(ip) ->
        if match?({:error, _}, :inet.parse_address(String.to_charlist(ip))) do
          new_ip = discover_ip()
          Logger.info("MEDIA_IP=#{ip} is not an IP literal; using discovered #{new_ip}")
          Application.put_env(:ex_kamailio, :media_ip, new_ip)
        end

      _ ->
        :ok
    end
  end

  defp discover_ip do
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
      {a, b, c, d} -> "#{a}.#{b}.#{c}.#{d}"
    end
  end
end
