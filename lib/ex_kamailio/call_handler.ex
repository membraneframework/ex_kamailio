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

  `use ExKamailio.CallHandler` supplies overridable defaults for `c:init/1`,
  `c:handle_delete/2` and `c:handle_idle/2`, so a handler need only define
  `c:handle_offer/3` and `c:handle_answer/3`. Register it in config — bare, or
  `{module, opts}` to pass options to `c:init/1`:

      config :ex_kamailio, call_handler: MyApp.KamailioHandler

  ## State is per call

  ex_kamailio runs one process per call (`ExKamailio.CallHandler.Server`), keyed by
  `session.call_id`. `c:init/1` seeds the state, your callbacks receive and return
  it, and it is dropped when the call stops — so per-call data (a pipeline pid, say)
  is safe in a bare field, and overlapping calls never share state. Routing by
  `call_id` also keeps a call consistent across the WebSocket connections Kamailio
  pools, even when its `offer`, `answer` and `delete` land on different ones.

  ## Call flow

  Kamailio relays each SDP exchange as an rtpengine command, in a fixed order:
  `offer`, then `answer` (either may be retransmitted), then `delete`. Peers are
  named by their RFC 3264 roles — the **offerer** proposes SDP, the **answerer**
  responds; in the initial `INVITE` (the only exchange implemented so far) that's
  caller and callee.

  1. `c:handle_offer/3` — the offerer's parsed SDP arrives. Bind a media socket and
     return SDP advertising it; that SDP is the offer the **answerer** sees.
  2. `c:handle_answer/3` — the answerer's parsed SDP arrives. Return SDP for the
     other direction; it becomes the answer the **offerer** receives.
  3. `c:handle_delete/2` — Kamailio tore the call down (`BYE`/`CANCEL`); release
     what you allocated.

  Each peer negotiates with you, not with the other: ex_kamailio never forwards one
  peer's SDP onward. Every callback gets the `%ExKamailio.Session{}`, which carries
  all four SDPs so far. To reject a command, raise — the crash is contained to that
  call's process, which replies to Kamailio with a Bencode error and stops.

  ## Optional callbacks

    * `c:handle_info/3` — handle plain messages in the call process (e.g. a
      `Membrane.Pipeline` reporting back). Without it, a stray message crashes the call.
    * `c:handle_idle/2` — called when no command arrives for `:idle_timeout`
      (default 30 min). The `use` default returns `{:stop, state}` to reap the call;
      return `{:ok, state}` to keep it. Reaping is **local only** — it frees this
      call's process and media but does not end the SIP dialog, so override it to
      check whether media is still flowing before letting a quiet call go.

  ## Callback latency budget

  Kamailio blocks a SIP worker waiting for each reply and, on timeout
  (`rtpengine_tout_ms`, default 1000 ms), disables the node for
  `rtpengine_disable_tout` (default 60 s) — failing every call meanwhile. So
  ex_kamailio waits at most `:rtpengine_command_timeout` (default 800 ms) for a
  callback, then returns an in-time error and tears that one call down (still
  running `c:handle_delete/2`). Keep slow work out of callbacks; if you raise
  `:rtpengine_command_timeout`, raise `rtpengine_tout_ms` with it.
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
