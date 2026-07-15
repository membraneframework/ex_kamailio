defmodule ExKamailio.CallHandler do
  @moduledoc """
  Behaviour for user-defined Kamailio rtpengine handlers.

  Implement this to plug your media-handling logic into ex_kamailio. The library
  handles the rtpengine protocol and stays a pure SDP shuttle: it allocates no media
  ports and picks no codecs. Your handler owns the media: it binds its own
  sockets, advertises them in the SDP it returns, and decides what to do with the
  stream (bridge it through Membrane, record, forward).

      defmodule MyApp.KamailioHandler do
        use ExKamailio.CallHandler

        @impl true
        def init(_session, _opts), do: {:ok, %{}}

        @impl true
        def handle_offer(from_offerer_sdp, session, state), do: {:ok, to_answerer_sdp, state}

        @impl true
        def handle_answer(from_answerer_sdp, session, state), do: {:ok, to_offerer_sdp, state}
      end

  `use ExKamailio.CallHandler` supplies overridable defaults for
  `c:handle_delete/2`, `c:handle_idle/2` and `c:handle_info/3`, so an
  implementation defines `c:init/2`, `c:handle_offer/3` and `c:handle_answer/3`.
  Register it in config, either bare or as `{module, opts}` to pass options to
  `c:init/2`:

      config :ex_kamailio, call_handler: MyApp.KamailioHandler

  When `:call_handler` is unset, `ExKamailio.CallHandler.Default` is used: it
  returns each peer's SDP unchanged so the app stays functional out of the box
  without touching the media.

  ## Call flow

  Kamailio relays each SDP exchange as an rtpengine command, in a fixed order:
  `offer`, then `answer` (either may be retransmitted), then `delete`. Peers are
  named by their RFC 3264 roles: the **offerer** proposes SDP, the **answerer**
  responds. In the initial `INVITE` (the only exchange implemented so far) that's
  caller and callee.

  1. `c:init/2` — seed the call's state.
  2. `c:handle_offer/3` — the offerer's parsed SDP arrives. You can e.g. bind a
     media socket and return SDP advertising it; the SDP returned from this
     callback is the offer the **answerer** sees.
  3. `c:handle_answer/3` — the answerer's parsed SDP arrives. Return SDP for the
     other direction; it becomes the answer the **offerer** receives.
  4. `c:handle_delete/2` — Kamailio tore the call down (`BYE`/`CANCEL`); release
     what you allocated.

  Every callback gets the session, filled in as the call progresses with the
  SDPs and call metadata accumulated so far.

  When Kamailio retransmits an `offer` or `answer`, sending the same SDP again,
  the call process replies with the SDP its callback returned the first time and
  does not run `c:handle_offer/3` or `c:handle_answer/3` again.

  ## Optional callbacks

    * `c:handle_info/3` — handle plain messages sent to the call process (e.g. a
      `Membrane.Pipeline` reporting back). By default it logs the message at
      debug level; override it to react to such messages.
    * `c:handle_idle/2` — called when no command arrives for `:idle_timeout`
      (default 30 min). The `use` default returns `{:stop, state}` to reap the call;
      return `{:ok, state}` to keep it. Reaping is **local only**: it frees this
      call's process but does not end the SIP dialog.

  ## Callback latency budget

  Kamailio blocks a SIP worker waiting for each reply and, on timeout
  (`rtpengine_tout_ms`, default 1000 ms), disables the node for
  `rtpengine_disable_tout` (default 60 s), failing every call meanwhile. So
  ex_kamailio waits at most `:callback_timeout` (default 800 ms) for a
  callback, then returns an in-time error and tears that one call down (still
  running `c:handle_delete/2`). Keep slow work out of callbacks; if you increase
  `:callback_timeout`, increase `rtpengine_tout_ms` with it.

  The 200 ms gap between `:callback_timeout` and `rtpengine_tout_ms` has to
  cover the round-trip between the two nodes plus serialization, so Kamailio
  still hears back before it gives up. Over loopback that is negligible; across
  a network it is not, so if you suspect 200 ms is too tight, widen the gap:
  increase `rtpengine_tout_ms`, lower `:callback_timeout`, or both.
  """

  alias ExKamailio.Session

  @doc """
  Declares the behaviour and injects overridable defaults for `handle_delete/2`,
  `handle_idle/2` and `handle_info/3`. See the module doc.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)
      require Logger

      @impl true
      def handle_delete(_session, _state), do: :ok

      @impl true
      def handle_idle(_session, state), do: {:stop, state}

      @impl true
      def handle_info(message, _session, state) do
        Logger.debug("unhandled message #{inspect(message)}")
        {:ok, state}
      end

      defoverridable handle_delete: 2, handle_idle: 2, handle_info: 3
    end
  end

  @type state :: term()

  @callback init(session :: Session.t(), opts :: keyword()) :: {:ok, state()}

  @callback handle_offer(offer :: ExSDP.t(), Session.t(), state()) ::
              {:ok, reply :: ExSDP.t(), state()}

  @callback handle_answer(answer :: ExSDP.t(), Session.t(), state()) ::
              {:ok, reply :: ExSDP.t(), state()}

  @callback handle_info(message :: term(), Session.t(), state()) :: {:ok, state()}

  @callback handle_idle(Session.t(), state()) ::
              {:ok, state()} | {:stop, state()}

  @callback handle_delete(Session.t(), state()) :: :ok

  @optional_callbacks handle_info: 3, handle_idle: 2, handle_delete: 2
end
