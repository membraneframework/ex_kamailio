defmodule ExKamailio.CallHandler do
  @moduledoc """
  Behaviour for the module that handles each call's media.

  ex_kamailio speaks the rtpengine protocol with Kamailio and passes SDP
  between it and this module, allocating no ports and picking no codecs. Which
  sockets to advertise in the returned SDP and what to do with the media is
  the handler's business.

      defmodule MyApp.KamailioHandler do
        use ExKamailio.CallHandler

        @impl true
        def init(_session, _opts), do: {:ok, %{}}

        @impl true
        def handle_offer(from_offerer_sdp, session, state), do: {:ok, to_answerer_sdp, state}

        @impl true
        def handle_answer(from_answerer_sdp, session, state), do: {:ok, to_offerer_sdp, state}
      end

  `use ExKamailio.CallHandler` brings overridable defaults for
  `c:handle_delete/2`, `c:handle_idle/2` and `c:handle_info/3`, so an
  implementation needs `c:init/2`, `c:handle_offer/3` and `c:handle_answer/3`.
  Register it in config, bare or as `{module, opts}` to pass options to
  `c:init/2`:

      config :ex_kamailio, call_handler: MyApp.KamailioHandler

  Without it, `#{inspect(ExKamailio.Config.default_call_handler())}` is used,
  which returns each peer's SDP unchanged.

  ## Call flow

  Kamailio relays each SDP exchange as an rtpengine command, in a fixed order:
  `offer`, then `answer` (either may be retransmitted), then `delete`. Peers are
  named by their RFC 3264 roles: the **offerer** proposes SDP, the **answerer**
  responds. In the initial `INVITE`, the only exchange implemented so far, that
  is caller and callee.

  1. `c:init/2` seeds the state.
  2. `c:handle_offer/3` gets the offerer's SDP. It may e.g. bind a socket and
     advertise it in the SDP it returns, which is the offer the answerer sees.
  3. `c:handle_answer/3` gets the answerer's SDP. The SDP it returns is the
     answer the offerer gets.
  4. `c:handle_delete/2` runs when Kamailio tears the call down (`BYE`,
     `CANCEL`), to release what was allocated.

  Every callback gets the `ExKamailio.Session`, which fills up with the SDPs
  as the call progresses. A retransmitted `offer` or `answer` is answered with
  the SDP the callback returned the first time, without running it again.

  ## Optional callbacks

    * `c:handle_info/3` gets messages sent to the call process, e.g. by a
      `Membrane.Pipeline`. The default logs them at debug level.
    * `c:handle_idle/2` runs when no command arrives for `:idle_timeout`
      (default 30 min). The default returns `{:stop, state}`, which runs
      `c:handle_delete/2` and stops the process; `{:ok, state}` keeps the call.
      Stopping only frees the process, the SIP dialog goes on.

  ## Callback deadline

  Kamailio waits `rtpengine_tout_ms` (default 1000 ms) for each reply, and when
  it runs out it stops using ex_kamailio for `rtpengine_disable_tout` (default
  60 s), failing every call meanwhile. So a callback gets `:callback_timeout`
  (default 800 ms); past that ex_kamailio replies with an error in time and
  tears that call down, `c:handle_delete/2` included. Keep slow work out of
  callbacks.

  The 200 ms left have to cover the round trip and serialization. That is
  nothing over loopback and may not be over a network, so widen the gap then:
  raise `rtpengine_tout_ms` or lower `:callback_timeout`.
  """

  alias ExKamailio.Session

  @doc """
  Declares the behaviour and injects overridable defaults for `handle_delete/2`,
  `handle_idle/2` and `handle_info/3`.
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
