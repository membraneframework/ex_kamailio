defmodule ExKamailio.CallHandler do
  @moduledoc """
  Behaviour for the module that handles each call's media.

  ex_kamailio speaks the rtpengine protocol with Kamailio and hands each SDP
  to an implementation of this behaviour; it allocates no ports and picks no
  codecs. The handler binds its own sockets, advertises them in the SDP it
  returns, and does what it wants with the media.

      defmodule MyApp.KamailioHandler do
        use ExKamailio.CallHandler

        @impl true
        def init(_session, _opts), do: {:ok, %{}}

        @impl true
        def handle_offer(from_offerer_sdp, session, state), do: {:ok, to_answerer_sdp, state}

        @impl true
        def handle_answer(from_answerer_sdp, session, state), do: {:ok, to_offerer_sdp, state}
      end

  `use ExKamailio.CallHandler` defines overridable defaults for
  `c:handle_delete/2`, `c:handle_idle/2` and `c:handle_info/3`, leaving
  `c:init/2`, `c:handle_offer/3` and `c:handle_answer/3` to the implementation.
  Register it in config, bare or as `{module, opts}` to pass options to
  `c:init/2`:

      config :ex_kamailio, call_handler: MyApp.KamailioHandler

  Without it, `#{inspect(ExKamailio.Config.default_call_handler())}` is used,
  which returns each peer's SDP unchanged.

  ## Call flow

  Kamailio relays each SDP exchange as an rtpengine command, in a fixed order:
  `offer`, then `answer` (either may be retransmitted), then `delete`. Peers are
  named by their RFC 3264 roles: the **offerer** proposes SDP, the **answerer**
  responds. In the initial `INVITE`, the only exchange supported so far, the
  offerer is the caller.

  1. `c:init/2` seeds the state.
  2. `c:handle_offer/3` gets the offerer's SDP and returns the offer the
     answerer sees, typically advertising a socket the handler just bound.
  3. `c:handle_answer/3` gets the answerer's SDP. The SDP it returns is the
     answer the offerer gets.
  4. `c:handle_delete/2` runs when Kamailio sends `delete`, to release what
     was allocated. The shipped config sends it on `BYE` only; a cancelled or
     rejected `INVITE` leaves the call to the idle timeout.

  Every callback gets the `ExKamailio.Session`, which fills up with the SDPs
  as the call progresses. A retransmitted `offer` or `answer` is answered with
  the SDP the callback returned the first time, without running it again. A
  callback that raises or returns the wrong shape kills the call process;
  Kamailio gets an error reply and `c:handle_delete/2` does not run.

  ## Optional callbacks

    * `c:handle_info/3` gets messages sent to the call process, e.g. by a
      `Membrane.Pipeline`. The default logs them at debug level.
    * `c:handle_idle/2` runs when no command arrives for `:idle_timeout`
      (default 30 min). The default returns `{:stop, state}`, which runs
      `c:handle_delete/2` and stops the process; `{:ok, state}` keeps the call.
      Stopping only frees the process; the SIP dialog goes on.

  ## Callback deadline

  Kamailio waits `rtpengine_tout_ms` (default 1000 ms) for each reply. A
  single late reply makes it mark ex_kamailio as down for
  `rtpengine_disable_tout` (default 60 s), and every call in that window
  fails on the spot, whether ex_kamailio has recovered or not.

  That is why a callback gets `:callback_timeout` (default 800 ms). Past it,
  ex_kamailio replies with an error while Kamailio is still listening and
  tears that one call down, `c:handle_delete/2` included. Losing one call
  beats losing a minute of all of them, so keep slow work out of callbacks.

  The remaining 200 ms cover serialization and the round trip to Kamailio.
  Over loopback that is plenty; across a network it may not be, so raise
  `rtpengine_tout_ms` or lower `:callback_timeout`.
  """

  alias ExKamailio.Session

  @doc "Declares the behaviour and the overridable defaults listed above."
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
