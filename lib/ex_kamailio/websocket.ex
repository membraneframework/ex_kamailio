defmodule ExKamailio.WebSocket do
  @moduledoc false
  # WebSock handler for Kamailio's rtpengine `ng` protocol. Each connection is one
  # WebSocket process, a thin router: it decodes the `<cookie> <payload>` frame,
  # parses the SDP, and dispatches to the call's process (`CallHandler.Server`,
  # keyed by `call_id` in `ExKamailio.CallRegistry`). The only module that speaks
  # rtpengine directly.

  @behaviour WebSock
  require Logger

  alias ExKamailio.{CallHandler, Config, Session}

  @impl true
  def init(_args) do
    {handler_mod, handler_opts} = Config.call_handler()
    {:ok, %{handler_mod: handler_mod, handler_opts: handler_opts}}
  end

  @impl true
  def handle_in({frame, [opcode: :text]}, state) do
    case String.split(frame, " ", parts: 2) do
      [cookie, body] ->
        case Bento.decode(body) do
          {:ok, %{"command" => cmd} = decoded} ->
            dispatch(cmd, cookie, decoded, state)

          _undecodable ->
            push_error(cookie, "unsupported", state)
        end

      _no_cookie ->
        Logger.warning("rtpengine frame missing cookie: #{inspect(frame)}")
        {:ok, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("unhandled message #{inspect(msg)}")
    {:ok, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.debug("WS closing: #{inspect(reason)}")
    :ok
  end

  defp dispatch("ping", cookie, _cmd, state) do
    push(cookie, %{result: "pong"}, state)
  end

  defp dispatch("offer", cookie, cmd, state) do
    from_tag = fetch_id(cmd, "from-tag")

    with {:id, call_id} when is_binary(call_id) <- {:id, fetch_id(cmd, "call-id")},
         session = %Session{call_id: call_id, from_tag: from_tag},
         {:sdp, {:ok, offer_sdp}} <- {:sdp, parse_sdp(Map.get(cmd, "sdp"))},
         session = %{session | from_offerer_sdp: offer_sdp},
         {:ok, _pid} <-
           CallHandler.Server.start(%{
             call_id: call_id,
             from_tag: from_tag,
             impl: state.handler_mod,
             impl_opts: state.handler_opts
           }),
         {:ok, wire_sdp} <- CallHandler.Server.call_offer(call_id, session) do
      push(cookie, %{result: "ok", sdp: wire_sdp}, state)
    else
      {:id, nil} ->
        push_missing_call_id(cookie, state)

      {:sdp, {:error, reason}} ->
        handle_sdp_parsing_error(reason, cookie, cmd, state)

      {:error, reason} ->
        Logger.error("handler offer failed: #{inspect(reason)}")
        push_error(cookie, "handler offer failed", state)
    end
  end

  defp dispatch("answer", cookie, cmd, state) do
    to_tag = fetch_id(cmd, "to-tag")

    with {:id, call_id} when is_binary(call_id) <- {:id, fetch_id(cmd, "call-id")},
         {:sdp, {:ok, answer_sdp}} <- {:sdp, parse_sdp(Map.get(cmd, "sdp"))},
         fields = %{to_tag: to_tag, from_answerer_sdp: answer_sdp},
         {:ok, wire_sdp} <- CallHandler.Server.call_answer(call_id, fields) do
      push(cookie, %{result: "ok", sdp: wire_sdp}, state)
    else
      {:id, nil} ->
        push_missing_call_id(cookie, state)

      {:sdp, {:error, reason}} ->
        handle_sdp_parsing_error(reason, cookie, cmd, state)

      {:error, reason} when reason in [:unknown, :late] ->
        Logger.warning("answer not pending: #{inspect(reason)}")
        push_error(cookie, "unknown call", state)

      {:error, reason} ->
        Logger.error("handler answer failed: #{inspect(reason)}")
        push_error(cookie, "handler answer failed", state)
    end
  end

  defp dispatch("delete", cookie, cmd, state) do
    case fetch_id(cmd, "call-id") do
      nil ->
        push_missing_call_id(cookie, state)

      call_id ->
        CallHandler.Server.call_delete(call_id)
        push(cookie, %{result: "ok"}, state)
    end
  end

  # TODO: the `update` and `query` rtpengine commands would slot in here as
  # their own dispatch/4 clauses above this fallback.
  defp dispatch(other, cookie, _cmd, state) do
    Logger.warning("unknown rtpengine command: #{inspect(other)}")
    push_error(cookie, "unsupported", state)
  end

  defp handle_sdp_parsing_error(error, cookie, cmd, state) do
    Logger.error("#{cmd["command"]} SDP parse failed: #{inspect(error)}")
    push_error(cookie, "invalid sdp", state)
  end

  defp parse_sdp(nil), do: {:error, :no_sdp}

  defp parse_sdp(text) when is_binary(text) do
    ExSDP.parse(text)
  rescue
    error -> {:error, error}
  end

  defp push(cookie, payload, state) do
    body = payload |> Bento.encode!() |> IO.iodata_to_binary()
    {:push, {:text, cookie <> " " <> body}, state}
  end

  defp push_error(cookie, reason, state) do
    push(cookie, %{"result" => "error", "error-reason" => reason}, state)
  end

  defp push_missing_call_id(cookie, state) do
    Logger.warning("rtpengine command missing call-id")
    push_error(cookie, "missing call-id", state)
  end

  defp fetch_id(cmd, key), do: Map.get(cmd, key)
end
