defmodule ExKamailio.Handler do
  @moduledoc """
  Behaviour for user-defined Kamailio rtpengine handlers.

  Implement this behaviour to plug your own media-handling logic into
  ex_kamailio. The library handles the rtpengine protocol details
  (WebSocket transport, Bencode encoding, local port allocation,
  session bookkeeping, SDP parsing). Your handler decides what to do
  with the media — bridge it through a Membrane pipeline, transcode
  it via FFmpeg, log it, forward it elsewhere, etc.

      defmodule MyApp.KamailioHandler do
        use ExKamailio.Handler

        @impl true
        def offer(session, state), do: {:ok, reply_sdp, state}

        @impl true
        def answer(session, state), do: {:ok, reply_sdp, state}
      end

  `use ExKamailio.Handler` declares the behaviour and provides default
  `c:init/1` (`{:ok, %{}}`) and `c:delete/2` (no-op) implementations, so a
  handler only has to define `c:offer/2` and `c:answer/2`. Override `init/1`
  or `delete/2` when you need setup or cleanup. Using `@behaviour
  ExKamailio.Handler` directly works too — then you must define all four.

  Register your handler module in config:

      config :ex_kamailio, handler: MyApp.KamailioHandler

  ## State is per call

  ex_kamailio keeps a separate `state` for each call, keyed by
  `session.call_id`. `c:init/1` seeds the state for each new call, your
  callbacks receive and return *that call's* state, and it is discarded on
  `c:delete/2`. You can safely keep per-call data (a pipeline pid, say) in a
  bare field — overlapping calls never share or overwrite each other's state.

  The state is stored centrally, keyed by `call_id` (not in the WebSocket
  process), so it is consistent even though Kamailio's rtpengine client pools
  several WebSocket connections and may deliver one call's `offer`, `answer`
  and `delete` over different connections.

  ## Lifecycle (per call)

  1. `c:init/1` seeds the state for the call.
  2. `c:offer/2` is called when Kamailio relays an SDP offer from the
     caller. The library has already allocated `session.caller_local`
     for you. Return the SDP to send back to Kamailio (which will be
     forwarded to the callee in an `INVITE`).
  3. `c:answer/2` is called when Kamailio relays the SDP answer from
     the callee. `session.callee_local` is already allocated. Return
     the SDP that will be forwarded back to the caller in `200 OK`.
  4. `c:delete/2` is called when Kamailio tears down the call; its state
     is then dropped.

  All callbacks may return `{:error, reason, state}`, which causes
  ex_kamailio to reply to Kamailio with a Bencode error and skip any
  further pipeline setup for that command.
  """

  alias ExKamailio.Session

  @doc """
  Declares the behaviour and injects default `init/1` and `delete/2`. See the
  module doc. Both defaults are overridable.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour ExKamailio.Handler

      @impl true
      def init(_opts), do: {:ok, %{}}

      @impl true
      def delete(_session, state), do: {:ok, state}

      defoverridable init: 1, delete: 2
    end
  end

  @type state :: term()

  @typedoc """
  The SDP a callback returns. An `%ExSDP{}` struct is canonical (build it from
  `session.offer_sdp`/`answer_sdp` with `ExKamailio.SDP.rewrite_endpoint/2`);
  a raw string is also accepted for log-only or hand-rolled handlers.
  """
  @type sdp :: ExSDP.t() | String.t()
  @type reason :: term()

  @callback init(opts :: keyword()) :: {:ok, state()}

  @callback offer(Session.t(), state()) ::
              {:ok, sdp(), state()} | {:error, reason(), state()}

  @callback answer(Session.t(), state()) ::
              {:ok, sdp(), state()} | {:error, reason(), state()}

  @callback delete(Session.t(), state()) :: {:ok, state()}
end
