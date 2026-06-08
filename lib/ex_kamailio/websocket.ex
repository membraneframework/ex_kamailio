defmodule ExKamailio.WebSocket do
  @moduledoc """
  WebSock handler for Kamailio's rtpengine `ng` control protocol over
  WebSocket.

  Each Kamailio connection produces one WebSocket process, which:

  1. Calls `c:ExKamailio.Handler.init/1` to set up per-connection state.
  2. On each incoming Bencode frame, decodes the `<cookie> <payload>`
     wire format, allocates local media ports for `offer`/`answer`,
     builds an `ExKamailio.Session`, and dispatches to the user's
     `Handler` callbacks.
  3. Encodes the handler's reply SDP back to Bencode and pushes it.

  This module is the only ex_kamailio code that talks the rtpengine
  protocol directly. Everything user-facing flows through
  `ExKamailio.Handler`.
  """

  @behaviour WebSock
  require Logger

  alias ExKamailio.{Endpoint, PortPool, SDP, Session, SessionTable, Utils}

  @impl true
  def init(_args) do
    state = %{
      handler_mod: Application.fetch_env!(:ex_kamailio, :handler),
      handler_opts: Application.get_env(:ex_kamailio, :handler_opts, []),
      media_ip: Utils.resolve_media_ip(Application.fetch_env!(:ex_kamailio, :media_ip))
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

  # -- offer: allocate local port for caller, hand off to user handler --

  defp do_offer(cookie, cmd, state) do
    call_id = fetch_id(cmd, "call-id")
    from_tag = fetch_id(cmd, "from-tag")
    offer_sdp_text = Map.get(cmd, "sdp")

    with {:ok, offer_sdp} <- SDP.parse(offer_sdp_text),
         {:ok, {caller_rtp, _}} <- PortPool.checkout({call_id, from_tag}) do
      caller_local = %Endpoint{
        ip: state.media_ip,
        rtp_port: caller_rtp,
        rtcp_port: caller_rtp + 1
      }

      session = %Session{
        call_id: call_id,
        from_tag: from_tag,
        state: :offered,
        caller_local: caller_local,
        caller_remote: SDP.first_audio_endpoint(offer_sdp),
        offer_sdp: offer_sdp
      }

      # init/1 seeds this call's handler state; the live state then lives in the
      # Session (global, keyed by call_id) and is threaded through answer/delete.
      result =
        safe_callback("offer", fn ->
          {:ok, seed_state} = state.handler_mod.init(state.handler_opts)
          state.handler_mod.offer(session, seed_state)
        end)

      case result do
        {:ok, reply_sdp, hstate} ->
          :ok = SessionTable.put(%Session{session | handler_state: hstate})

          reply =
            encode_reply(cookie, %{
              result: "ok",
              sdp: to_sdp_string(reply_sdp),
              rtp_port: caller_rtp,
              rtcp_port: caller_rtp + 1
            })

          {:push, reply, state}

        {:error, reason, _hstate} ->
          Logger.error("handler offer rejected: #{inspect(reason)}")
          :ok = PortPool.release({call_id, from_tag}, caller_rtp)

          {:push, reply_error(cookie, "handler rejected offer"), state}
      end
    else
      {:error, :no_ports} ->
        {:push, reply_error(cookie, "port pool exhausted"), state}

      {:error, reason} ->
        Logger.error("offer SDP parse failed: #{inspect(reason)}")
        {:push, reply_error(cookie, "invalid sdp"), state}
    end
  end

  # -- answer: allocate local port for callee, finalize session --

  defp do_answer(cookie, cmd, state) do
    call_id = fetch_id(cmd, "call-id")
    to_tag = fetch_id(cmd, "to-tag")
    answer_sdp_text = Map.get(cmd, "sdp")

    case SessionTable.get(call_id) do
      %Session{state: :answered, to_tag: ^to_tag, answer_reply_sdp: reply_sdp}
      when is_binary(reply_sdp) ->
        # Retransmitted answer for the same dialog — Kamailio forwards 200 OK
        # retransmissions through onreply_route, so rtpengine_answer() fires
        # again. The rtpengine protocol expects idempotent answers; replay
        # the cached reply instead of re-invoking the handler (which would
        # try to spawn a second pipeline / re-allocate ports).
        {:push, encode_reply(cookie, %{result: "ok", sdp: reply_sdp}), state}

      session ->
        do_fresh_answer(cookie, call_id, to_tag, answer_sdp_text, session, state)
    end
  end

  defp do_fresh_answer(cookie, call_id, to_tag, answer_sdp_text, prior_session, state) do
    with %Session{state: :offered} = session <- prior_session,
         {:ok, answer_sdp} <- SDP.parse(answer_sdp_text),
         {:ok, {callee_rtp, _}} <- PortPool.checkout({call_id, to_tag}) do
      callee_local = %Endpoint{
        ip: state.media_ip,
        rtp_port: callee_rtp,
        rtcp_port: callee_rtp + 1
      }

      session = %Session{
        session
        | state: :answered,
          to_tag: to_tag,
          callee_local: callee_local,
          callee_remote: SDP.first_audio_endpoint(answer_sdp),
          answer_sdp: answer_sdp
      }

      result =
        safe_callback("answer", fn ->
          state.handler_mod.answer(session, session.handler_state)
        end)

      case result do
        {:ok, reply_sdp, hstate} ->
          wire_sdp = to_sdp_string(reply_sdp)
          :ok = SessionTable.put(%Session{session | answer_reply_sdp: wire_sdp, handler_state: hstate})
          reply = encode_reply(cookie, %{result: "ok", sdp: wire_sdp})
          {:push, reply, state}

        {:error, reason, _hstate} ->
          Logger.error("handler answer rejected: #{inspect(reason)}")
          :ok = PortPool.release({call_id, to_tag}, callee_rtp)

          {:push, reply_error(cookie, "handler rejected answer"), state}
      end
    else
      nil ->
        Logger.warning("answer for unknown call_id=#{inspect(call_id)}")
        {:push, reply_error(cookie, "unknown call"), state}

      %Session{state: actual} ->
        Logger.warning("late answer for call_id=#{inspect(call_id)} in state=#{inspect(actual)}")
        {:push, reply_error(cookie, "unknown call"), state}

      {:error, :no_ports} ->
        {:push, reply_error(cookie, "port pool exhausted"), state}

      {:error, reason} ->
        Logger.error("answer SDP parse failed: #{inspect(reason)}")
        {:push, reply_error(cookie, "invalid sdp"), state}
    end
  end

  # -- delete: tear down session --

  defp do_delete(cookie, cmd, state) do
    call_id = fetch_id(cmd, "call-id")

    case SessionTable.get(call_id) do
      %Session{} = session ->
        # Best-effort teardown: even if the handler's delete crashes, we still
        # release ports and drop the session so a buggy handler can't leak them.
        safe_callback("delete", fn ->
          state.handler_mod.delete(session, session.handler_state)
        end)

        SessionTable.release_ports(session)
        :ok = SessionTable.delete(call_id)

        {:push, encode_reply(cookie, %{result: "ok"}), state}

      nil ->
        {:push, reply_error(cookie, "unknown call"), state}
    end
  end

  # Run a handler callback, turning any raise/throw/exit into the same
  # `{:error, reason, _}` reply the callback could have returned itself. A buggy
  # handler thus rejects one call cleanly instead of crashing the shared,
  # connection-pooled WebSocket process.
  defp safe_callback(label, fun) do
    fun.()
  rescue
    e ->
      Logger.error(
        "handler #{label} crashed: #{Exception.message(e)}\n" <>
          Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, {:crash, e}, nil}
  catch
    kind, reason ->
      Logger.error("handler #{label} #{inspect(kind)}: #{inspect(reason)}")
      {:error, {kind, reason}, nil}
  end

  # -- bencode/wire helpers --

  defp to_sdp_string(sdp) when is_binary(sdp), do: sdp
  defp to_sdp_string(%ExSDP{} = sdp), do: to_string(sdp)

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
