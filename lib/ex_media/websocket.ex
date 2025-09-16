defmodule ExMedia.WebSocket do
  @behaviour WebSock
  require Logger

  @impl true
  def init(_args) do
    {:ok, pid} = ExMedia.CommandHandler.Default.start_link([])
    {:ok, %{handler: pid}}
  end

  #{"0_6251_0 d7:command4:pinge", [opcode: :text]}
  @impl true
  def handle_in({ecommand, [opcode: :text]}, state) do
    [cookie, fullcommand] = String.split(ecommand, " ", parts: 2)
    with {:ok, %{"command" => comm} = decoded_command} <- Bento.decode(fullcommand) do
      handle_command(comm, cookie, decoded_command, state)
    else
      _ ->
        {:ok, bencode_error} = Bento.encode(%{"result" => "error", "error-reason" => "unsupported"})
        payload = IO.iodata_to_binary(bencode_error)
        {:push, {:text, <<cookie, " ", payload>>}, state}
    end
  end

  defp handle_command("ping", cookie, _command, state) do
    {:ok, bencode_pong} = Bento.encode(%{result: "pong"})
    payload = IO.iodata_to_binary(bencode_pong)
    Logger.info("pong #{inspect payload}")
     {:push, {:text, cookie <> " " <> payload}, state}
  end
  defp handle_command("offer", cookie, command, %{handler: pid} = state) do
    Logger.info("answer: #{inspect command}")
    {:ok, payload} = GenServer.call(pid, {:command, command})
    {:push, {:text, <<cookie::binary, " ", payload::binary>>}, state}
  end
  defp handle_command("answer", cookie, command, %{handler: pid} = state) do
    Logger.info("answer: #{inspect command}")
    {:ok, payload} = GenServer.call(pid, {:command, command})
    {:push, {:text, <<cookie::binary, " ", payload::binary>>}, state}
  end
  defp handle_command("delete", cookie, command, %{handler: pid} = state) do
    Logger.info(%{delete: command})
    {:ok, payload} = GenServer.call(pid, {:command, command})
    {:push, {:text, <<cookie::binary, " ", payload::binary>>}, state}
  end
  defp handle_command(comm, cookie, _, state) do
    Logger.info(%{"unknown command" => comm})
    {:ok, bencode_error} = Bento.encode(%{"result" => "error", "error-reason" => "unsupported"})
    payload = IO.iodata_to_binary(bencode_error)
    {:push, {:text, cookie <> " " <> payload}, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.info("unhandled message #{inspect msg}")
    {:ok, state}
  end

  @impl true
  def terminate(reason, %{handler: pid} = _state) do
    Logger.error("WS closing: #{inspect(reason)}")
    if Process.alive?(pid) do
      Logger.info("terminating command handler #{inspect pid}")
      GenServer.stop(pid, :shutdown)
    end
    :ok
  end
end
