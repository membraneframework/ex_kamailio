defmodule ExMedia.WebSocket do
  @behaviour WebSock
  require Logger

  @impl true
  def init(_args) do
    {:ok, pid} = ExMedia.CommandHandler.Default.start_link([])
    {:ok, %{handler: pid}}
  end

  @impl true
  def handle_in({"text", payload}, state) do
    case decode_message(payload) do
      {:ok, cmd} ->
        case GenServer.call(state.handler, {:command, cmd}, 60_000) do
          {:ok, reply} -> {:reply, {:text, reply}, state}
          {:error, reason} -> {:reply, {:text, error_reply(reason)}, state}
        end

      {:error, reason} ->
        {:reply, {:text, error_reply(reason)}, state}
    end
  end

  def handle_in(other, state) do
    IO.inspect(other)
    {:ok, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:ok, state}

  @impl true
  def terminate(_reason, _state), do: :ok

  # Accept JSON or a simple line-based format: "offer {json...}" / "delete {json...}"
  defp decode_message(payload) when is_binary(payload) do
    with {:json, {:ok, map}} <- {:json, Jason.decode(payload)},
         %{"command" => _} = map <- normalize_keys(map) do
      {:ok, map}
    else
      {:json, _} ->
        case String.trim(payload) do
          <<>> -> {:error, :empty}
          line -> parse_line_command(line)
        end
    end
  end

  defp parse_line_command(line) do
    # e.g. "offer {\"sdp\":\"...\",\"call_id\":\"abc\"}"
    case String.split(line, ~r/\s+/, parts: 2) do
      [cmd] -> {:ok, %{command: String.downcase(cmd)}}
      [cmd, rest] ->
        with {:ok, map} <- Jason.decode(rest),
             map <- normalize_keys(map) do
          {:ok, Map.put(map, :command, String.downcase(cmd))}
        else
          _ -> {:ok, %{command: String.downcase(cmd), raw: rest}}
        end
    end
  end

  defp normalize_keys(map) when is_map(map) do
    map
    |> Enum.into(%{}, fn {k, v} ->
      {normalize_key(k), v}
    end)
  end

  defp normalize_key(k) when is_binary(k), do: String.to_atom(k)
  defp normalize_key(k) when is_atom(k), do: k

  defp error_reply(reason) do
    Jason.encode!(%{result: "error", reason: inspect(reason)})
  end
end
