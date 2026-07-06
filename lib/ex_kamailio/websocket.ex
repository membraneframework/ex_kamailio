defmodule ExKamailio.WebSocket do
  @moduledoc false
  # WebSock handler for Kamailio's rtpengine `ng` protocol. Each connection is one
  # WebSocket process, a thin router: it decodes the `<cookie> <payload>` frame,
  # parses the SDP, and dispatches to the call's process (`CallHandler.Server`,
  # keyed by `call_id` in `ExKamailio.CallRegistry`). The only module that speaks
  # rtpengine directly.

  @behaviour WebSock
  require Logger

  alias ExKamailio.{CallHandler, ConstantsAndVariables, Session}

  @impl true
  def init(_args) do
    {handler_mod, handler_opts} = ConstantsAndVariables.call_handler()
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
    Logger.info("WS closing: #{inspect(reason)}")
    :ok
  end

  defp dispatch("ping", cookie, _cmd, state) do
    push(cookie, %{result: "pong"}, state)
  end

  defp dispatch("offer", cookie, cmd, state) do
    call_id = fetch_id(cmd, "call-id")
    from_tag = fetch_id(cmd, "from-tag")

    session = %Session{
      call_id: call_id,
      from_tag: from_tag
    }

    with {:sdp, {:ok, offer_sdp}} <- {:sdp, parse_sdp(Map.get(cmd, "sdp"))},
         session = %{session | from_offerer_sdp: offer_sdp},
         {:ok, _pid} <-
           CallHandler.Server.start_call(call_id, from_tag, state.handler_mod, state.handler_opts),
         {:ok, wire_sdp} <- CallHandler.Server.call_offer(call_id, session) do
      push(cookie, %{result: "ok", sdp: wire_sdp}, state)
    else
      {:sdp, {:error, reason}} ->
        handle_sdp_parsing_error(reason, cookie, cmd, state)

      {:error, reason} ->
        Logger.error("handler offer failed: #{inspect(reason)}")
        push_error(cookie, "handler offer failed", state)
    end
  end

  defp dispatch("answer", cookie, cmd, state) do
    to_tag = fetch_id(cmd, "to-tag")

    with {:sdp, {:ok, answer_sdp}} <- {:sdp, parse_sdp(Map.get(cmd, "sdp"))},
         fields = %{to_tag: to_tag, from_answerer_sdp: answer_sdp},
         {:ok, wire_sdp} <- CallHandler.Server.call_answer(fetch_id(cmd, "call-id"), fields) do
      push(cookie, %{result: "ok", sdp: wire_sdp}, state)
    else
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
    case CallHandler.Server.call_delete(fetch_id(cmd, "call-id")) do
      :ok ->
        push(cookie, %{result: "ok"}, state)

      {:error, :unknown} ->
        push_error(cookie, "unknown call", state)

      {:error, _down} ->
        # Process already gone — the call is torn down, which is what delete wants.
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

  defp fetch_id(cmd, key), do: Map.get(cmd, key, "unknown")
end
