defmodule ExKamailio.CallHandler do
  @moduledoc """
  Behaviour for user-defined Kamailio rtpengine handlers.

  Implement this to plug your media-handling logic into ex_kamailio. The library
  handles the rtpengine protocol (WebSocket transport, Bencode, session
  bookkeeping, SDP parsing) and stays a pure SDP shuttle: it allocates no media
  ports and picks no codecs. Your handler owns the media — it binds its own
  sockets, advertises them in the SDP it returns, and decides what to do with the
  stream (bridge it through Membrane, transcode via FFmpeg, record, forward).

      defmodule MyApp.KamailioHandler do
        use ExKamailio.CallHandler

        @impl true
        def handle_offer(offer, session, state), do: {:ok, reply_sdp, state}

        @impl true
        def handle_answer(answer, session, state), do: {:ok, reply_sdp, state}
      end

  `use ExKamailio.CallHandler` declares the behaviour and supplies overridable
  defaults for `c:init/1` (`{:ok, %{}}`), `c:handle_delete/2` (no-op) and
  `c:handle_idle/2` (reap the call when idle), so a handler need only define
  `c:handle_offer/3` and `c:handle_answer/3`. `@behaviour ExKamailio.CallHandler`
  works too, but then you define every non-optional callback yourself.

  Register the handler in config — bare, or `{module, opts}` to pass options to
  `c:init/1`:

      config :ex_kamailio, call_handler: MyApp.KamailioHandler

  ## State is per call

  ex_kamailio runs one process per call (`ExKamailio.CallHandler.Server`), looked
  up by `session.call_id`. `c:init/1` seeds the state, the process holds it, your
  callbacks receive and return it, and it is dropped when the call stops.
  Overlapping calls never share state, so per-call data (a pipeline pid, say) is
  safe in a bare field.

  This is also what keeps a call consistent even though Kamailio pools several
  WebSocket connections and may deliver one call's `offer`, `answer` and `delete`
  over different ones: each is routed to the call's process by `call_id`.

  ## Call flow

  Kamailio relays each SDP exchange as an rtpengine command, in a fixed order:
  `offer`, then `answer` (either may be retransmitted), then `delete`. An `answer`
  for a call that was never offered is rejected before reaching your handler.

  Peers are named by their RFC 3264 roles — the **offerer** proposes SDP, the
  **answerer** responds. In the initial `INVITE` (the only exchange implemented so
  far) the offerer is the caller, the answerer the callee.

  1. `c:init/1` — seed the call's state.
  2. `c:handle_offer/3` — the offerer's `INVITE` arrived; its parsed SDP is the
     first argument. Bind a media socket and return SDP advertising it; that SDP
     is the offer the **answerer** sees in the forwarded `INVITE`.
  3. `c:handle_answer/3` — the answerer accepted; its parsed SDP is the first
     argument. Return SDP advertising your socket for the other direction; it
     becomes the answer the **offerer** receives in the `200 OK`.
  4. `c:handle_delete/2` — Kamailio tore the call down (`BYE`/`CANCEL`); release
     what you allocated. The call's state is dropped afterwards.

  Each peer negotiates with you, not with the other peer: ex_kamailio never
  forwards one peer's SDP to the other. The `%ExKamailio.Session{}` passed to
  every callback holds the full record — all four SDPs, as far as the call has got.

  To reject a command, raise: the crash is contained to that call's process,
  ex_kamailio replies to Kamailio with a Bencode error, and the call is gone.

  ## Optional callbacks

    * `c:handle_info/3` — receive plain messages in the call process (e.g. a
      `Membrane.Pipeline` reporting back), delivered with the call's session and
      state. Without it, a stray message crashes the call process.
    * `c:handle_idle/2` — a call that never receives a `delete` (dropped
      signaling) would live forever, so each call arms an idle timer
      (`:idle_timeout`, default 30 min, reset on `offer`/`answer`). On expiry the
      `use` default returns `{:stop, state}` and the call is reaped. This is local
      cleanup only: it frees this call's process and media but does **not** end the
      SIP dialog — the peers stay in the call until one hangs up. The timer counts
      signaling, not media, so it cannot tell an abandoned call from a long quiet
      one; override to inspect the media and keep the call alive with `{:ok, state}`.

  ## Callback latency budget

  Kamailio's rtpengine module blocks a SIP worker waiting for each reply and gives
  up after `rtpengine_tout_ms` (default 1000 ms); a miss also marks the node
  disabled for `rtpengine_disable_tout` (default 60 s), failing every call
  meanwhile. ex_kamailio therefore waits at most `:rtpengine_command_timeout`
  (config, default 800 ms) for a callback, then replies with an in-time error —
  that one call fails (it is torn down, `c:handle_delete/2` still runs) but the
  node stays up. Keep slow work out of these callbacks; if you raise
  `:rtpengine_command_timeout`, raise Kamailio's `rtpengine_tout_ms` with it.
  """

  alias ExKamailio.Session

  @doc """
  Declares the behaviour and injects overridable defaults for `init/1`,
  `handle_delete/2` and `handle_idle/2`. See the module doc.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)

      @impl true
      def init(_opts), do: {:ok, %{}}

      @impl true
      def handle_delete(_session, state), do: {:ok, state}

      @impl true
      def handle_idle(_session, state), do: {:stop, state}

      defoverridable init: 1, handle_delete: 2, handle_idle: 2
    end
  end

  @type state :: term()

  @callback init(opts :: keyword()) :: {:ok, state()}

  @callback handle_offer(offer :: ExSDP.t(), Session.t(), state()) ::
              {:ok, reply :: ExSDP.t(), state()}

  @callback handle_answer(answer :: ExSDP.t(), Session.t(), state()) ::
              {:ok, reply :: ExSDP.t(), state()}

  @callback handle_info(message :: term(), Session.t(), state()) :: {:ok, state()}

  @callback handle_idle(Session.t(), state()) ::
              {:ok, state()} | {:stop, state()}

  @callback handle_delete(Session.t(), state()) :: {:ok, state()}

  @optional_callbacks handle_info: 3
end
