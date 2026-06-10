defmodule ExKamailio.WebSocket do
  @moduledoc """
  WebSock handler for Kamailio's rtpengine `ng` control protocol over
  WebSocket.

  Each Kamailio connection produces one WebSocket process, which is a thin
  router: it decodes the `<cookie> <payload>` wire format, parses the SDP into
  an `ExKamailio.Session`, and dispatches the command to the call's own process
  (`ExKamailio.Handler.Server`, looked up by `call_id` in
  `ExKamailio.CallRegistry`). The call process runs the user's `Handler`
  callbacks and holds that call's state; this process only ships SDP in and out.

  This module is the only ex_kamailio code that talks the rtpengine protocol
  directly. Everything user-facing flows through `ExKamailio.Handler`.
  """

  @behaviour WebSock
  require Logger

  alias ExKamailio.{Handler, SDP, Session}

  @impl true
  def init(_args) do
    state = %{
      handler_mod: Application.fetch_env!(:ex_kamailio, :handler),
      handler_opts: Application.get_env(:ex_kamailio, :handler_opts, [])
    }

    {:ok, state}
  end

  @impl true
  def handle_in({frame, [opcode: :text]}, state) do
    case String.split(frame, " ", parts: 2) do
      [cookie, body] ->
        case Bento.decode(body) do
          {:ok, %{"command" => cmd} = decoded} ->
            dispatch(cmd, cookie, decoded, state)

          _ ->
            {:push, reply_error(cookie, "unsupported"), state}
        end

      _ ->
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

  # -- command dispatch --

  defp dispatch("ping", cookie, _cmd, state) do
    {:push, encode_reply(cookie, %{result: "pong"}), state}
  end

  defp dispatch("offer", cookie, cmd, state), do: do_offer(cookie, cmd, state)
  defp dispatch("answer", cookie, cmd, state), do: do_answer(cookie, cmd, state)
  defp dispatch("delete", cookie, cmd, state), do: do_delete(cookie, cmd, state)

  defp dispatch(other, cookie, _cmd, state) do
    Logger.warning("unknown rtpengine command: #{inspect(other)}")
    {:push, reply_error(cookie, "unsupported"), state}
  end

  # -- offer: parse SDP, hand off to the call process --

  defp do_offer(cookie, cmd, state) do
    call_id = fetch_id(cmd, "call-id")
    from_tag = fetch_id(cmd, "from-tag")

    case SDP.parse(Map.get(cmd, "sdp")) do
      {:ok, offer_sdp} ->
        session = %Session{
          call_id: call_id,
          from_tag: from_tag,
          state: :offered,
          caller_remote: SDP.first_audio_endpoint(offer_sdp),
          offer_sdp: offer_sdp
        }

        offer_call(cookie, call_id, session, state)

      {:error, reason} ->
        Logger.error("offer SDP parse failed: #{inspect(reason)}")
        {:push, reply_error(cookie, "invalid sdp"), state}
    end
  end

  defp offer_call(cookie, call_id, session, state) do
    with {:ok, _pid} <- Handler.Server.start_call(call_id, state.handler_mod, state.handler_opts),
         {:ok, wire_sdp} <- Handler.Server.call_offer(call_id, session) do
      {:push, encode_reply(cookie, %{result: "ok", sdp: wire_sdp}), state}
    else
      {:error, reason} ->
        Logger.error("handler offer failed: #{inspect(reason)}")
        {:push, reply_error(cookie, "handler offer failed"), state}
    end
  end

  # -- answer: parse SDP, finalize the call --

  defp do_answer(cookie, cmd, state) do
    call_id = fetch_id(cmd, "call-id")
    to_tag = fetch_id(cmd, "to-tag")

    case SDP.parse(Map.get(cmd, "sdp")) do
      {:ok, answer_sdp} ->
        fields = %{
          to_tag: to_tag,
          answer_sdp: answer_sdp,
          callee_remote: SDP.first_audio_endpoint(answer_sdp)
        }

        answer_call(cookie, call_id, fields, state)

      {:error, reason} ->
        Logger.error("answer SDP parse failed: #{inspect(reason)}")
        {:push, reply_error(cookie, "invalid sdp"), state}
    end
  end

  defp answer_call(cookie, call_id, fields, state) do
    case Handler.Server.call_answer(call_id, fields) do
      {:ok, wire_sdp} ->
        {:push, encode_reply(cookie, %{result: "ok", sdp: wire_sdp}), state}

      {:error, reason} when reason in [:unknown, :late] ->
        Logger.warning("answer for call_id=#{inspect(call_id)} not pending: #{inspect(reason)}")
        {:push, reply_error(cookie, "unknown call"), state}

      {:error, reason} ->
        Logger.error("handler answer failed: #{inspect(reason)}")
        {:push, reply_error(cookie, "handler answer failed"), state}
    end
  end

  # -- delete: tear down the call process --

  defp do_delete(cookie, cmd, state) do
    call_id = fetch_id(cmd, "call-id")

    case Handler.Server.call_delete(call_id) do
      :ok ->
        {:push, encode_reply(cookie, %{result: "ok"}), state}

      {:error, :unknown} ->
        {:push, reply_error(cookie, "unknown call"), state}

      {:error, _down} ->
        # Process already gone — the call is torn down, which is what delete wants.
        {:push, encode_reply(cookie, %{result: "ok"}), state}
    end
  end

  # -- bencode/wire helpers --

  defp encode_reply(cookie, payload) do
    body = payload |> Bento.encode!() |> IO.iodata_to_binary()
    {:text, cookie <> " " <> body}
  end

  defp reply_error(cookie, reason) do
    encode_reply(cookie, %{"result" => "error", "error-reason" => reason})
  end

  defp fetch_id(cmd, key, default \\ "unknown") do
    Map.get(cmd, key, default)
  end
end
