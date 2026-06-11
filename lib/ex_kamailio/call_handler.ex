defmodule ExKamailio.CallHandler do
  @moduledoc """
  Behaviour for user-defined Kamailio rtpengine handlers.

  Implement this behaviour to plug your own media-handling logic into
  ex_kamailio. The library handles the rtpengine protocol details
  (WebSocket transport, Bencode encoding, session bookkeeping, SDP
  parsing) and stays a pure SDP shuttle — it does not allocate media
  ports or pick codecs. Your handler owns the media: it binds its own
  sockets, advertises them in the SDP it returns, and decides what to do
  with the stream — bridge it through a Membrane pipeline, transcode it
  via FFmpeg, log it, forward it elsewhere, etc.

      defmodule MyApp.KamailioHandler do
        use ExKamailio.CallHandler

        @impl true
        def handle_offer(offer, session, state), do: {:ok, reply_sdp, state}

        @impl true
        def handle_answer(answer, session, state), do: {:ok, reply_sdp, state}
      end

  `use ExKamailio.CallHandler` declares the behaviour and provides overridable
  defaults for `c:init/1` (`{:ok, %{}}`), `c:handle_delete/2` (no-op) and
  `c:handle_timeout/2` (tear the call down), so a handler only has to define
  `c:handle_offer/3` and `c:handle_answer/3`. Using `@behaviour ExKamailio.CallHandler` directly
  works too — then you must define all non-optional callbacks.

  Register your handler module in config — bare, or as `{module, opts}` to
  pass options to `c:init/1`:

      config :ex_kamailio, call_handler: MyApp.KamailioHandler

  ## State is per call

  ex_kamailio runs **one process per call** (`ExKamailio.CallHandler.Server`),
  looked up by `session.call_id` through `ExKamailio.CallRegistry`. `c:init/1`
  seeds the state for each new call, that process holds it in its own memory,
  your callbacks receive and return it, and it is discarded when the process
  stops on `c:handle_delete/2`. You can safely keep per-call data (a pipeline pid, say)
  in a bare field — each call has its own process, so overlapping calls never
  share or overwrite each other's state.

  The registry is what keeps a call consistent even though Kamailio's rtpengine
  client pools several WebSocket connections and may deliver one call's `offer`,
  `answer` and `delete` over different connections: each lands on an arbitrary
  WebSocket process, which routes it to the call's process by `call_id`.

  ## Reacting to other processes

  Define the optional `c:handle_info/3` to receive plain messages in the call
  process — e.g. a `Membrane.Pipeline` or downstream `GenServer` reporting back.
  The message is delivered alongside the call's `session` and state. Without it,
  a stray message crashes the call process (`UndefinedFunctionError`).

  ## Call timeout

  If a call never receives a Kamailio `delete` (dropped signaling), its process
  would otherwise live forever. Each call arms a timer — `:call_timeout` in
  config, default 30 minutes, reset on `offer`/`answer`. On expiry the library
  calls `c:handle_timeout/2`; the `use` default tears the call down (runs
  `c:handle_delete/2`, then stops).

  The timer counts signaling, not media: no command arrives between the answer
  and the hangup, so a call outliving `:call_timeout` hits it with media still
  flowing. ex_kamailio never sees the RTP — only your handler can tell an
  abandoned call from a long one. Override `c:handle_timeout/2` to check and
  extend (`{:noreply, state}`).

  ## Call flow

  Kamailio relays each SDP exchange of a call as an rtpengine command, in a
  fixed order: `offer`, then `answer` (either may be retransmitted), then
  `delete`. An `answer` for a call that was never offered is rejected without
  reaching your handler, so `c:handle_offer/3` always runs before
  `c:handle_answer/3`.

  The peers are named by their RFC 3264 roles: the **offerer** proposes SDP,
  the **answerer** responds. In the initial `INVITE` — the only exchange
  ex_kamailio implements so far — the offerer is the caller and the answerer
  is the callee; in a re-INVITE (rtpengine `update`, on the roadmap) either
  peer may offer.

  1. `c:init/1` seeds the state for the call.
  2. `c:handle_offer/3` — the offerer's `INVITE` arrived; its parsed SDP offer
     is the first argument. Bind a media socket and return SDP advertising it:
     that SDP becomes the *offer* the **answerer** sees in the forwarded
     `INVITE`. Nothing is sent to the offerer at this stage.
  3. `c:handle_answer/3` — the answerer accepted; its parsed SDP answer is the
     first argument. Return SDP advertising your socket for the other
     direction: that SDP becomes the *answer* the **offerer** receives in the
     forwarded `200 OK`, completing the exchange.
  4. `c:handle_delete/2` — Kamailio tears the call down (`BYE`/`CANCEL`); the
     call's state is dropped afterwards. Release whatever you allocated.

  Media-wise, each peer ends up negotiating with you: the offerer's offer is
  answered by the SDP you return from `c:handle_answer/3`, and the offer the
  answerer responds to is the one you returned from `c:handle_offer/3`.
  ex_kamailio never forwards one peer's SDP to the other on its own. The
  `%ExKamailio.Session{}` passed to every callback keeps the full record —
  all four SDPs, as far as the call has got.

  Callbacks have no error return — to reject a command, raise. The crash
  is contained to that call's process: ex_kamailio replies to Kamailio
  with a Bencode error and the call is gone.

  ## Callback latency budget

  Kamailio's rtpengine module blocks a SIP worker while it waits for the
  reply to each command and gives up after `rtpengine_tout_ms` (default
  1000 ms). Missing that deadline does more than fail the one command:
  Kamailio marks the node disabled for `rtpengine_disable_tout` (default
  60 s), failing every call's commands meanwhile. ex_kamailio therefore
  waits at most `:rtpengine_command_timeout` (config, default 800 ms) for a
  callback, then replies with an in-time error — that call fails (the
  call process is told to tear down; `c:handle_delete/2` still runs) but
  the node stays up. Keep slow work (transcoder warm-up, external
  lookups) out of these callbacks; if you must raise `:rtpengine_command_timeout`,
  raise Kamailio's `rtpengine_tout_ms` with it.
  """

  alias ExKamailio.Session

  @doc """
  Declares the behaviour and injects overridable defaults for `init/1`,
  `handle_delete/2` and `handle_timeout/2`. See the module doc.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)

      @impl true
      def init(_opts), do: {:ok, %{}}

      @impl true
      def handle_delete(_session, state), do: {:ok, state}

      @impl true
      def handle_timeout(_session, state), do: {:stop, state}

      defoverridable init: 1, handle_delete: 2, handle_timeout: 2
    end
  end

  @type state :: term()

  @callback init(opts :: keyword()) :: {:ok, state()}

  @callback handle_offer(offer :: ExSDP.t(), Session.t(), state()) ::
              {:ok, reply :: ExSDP.t(), state()}

  @callback handle_answer(answer :: ExSDP.t(), Session.t(), state()) ::
              {:ok, reply :: ExSDP.t(), state()}

  @callback handle_info(message :: term(), Session.t(), state()) :: {:ok, state()}

  @callback handle_timeout(Session.t(), state()) ::
              {:stop, state()} | {:noreply, state()}

  @callback handle_delete(Session.t(), state()) :: {:ok, state()}

  @optional_callbacks handle_info: 3
end
