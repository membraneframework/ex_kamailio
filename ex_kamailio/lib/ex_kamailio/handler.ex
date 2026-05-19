defmodule ExKamailio.Handler do
  @moduledoc """
  Behaviour for user-defined Kamailio rtpengine handlers.

  Implement this behaviour to plug your own media-handling logic into
  ex_kamailio. The library handles the rtpengine protocol details
  (WebSocket transport, Bencode encoding, local port allocation,
  session bookkeeping, SDP parsing). Your handler decides what to do
  with the media — bridge it through a Membrane pipeline, transcode
  it via FFmpeg, log it, forward it elsewhere, etc.

  Register your handler module in config:

      config :ex_kamailio, handler: MyApp.KamailioHandler

  ## Lifecycle

  1. `c:init/1` is called once when a new WebSocket connection is
     accepted from Kamailio. Use it to set up per-connection state.
  2. `c:offer/2` is called when Kamailio relays an SDP offer from the
     caller. The library has already allocated `session.caller_local`
     for you. Return the SDP to send back to Kamailio (which will be
     forwarded to the callee in an `INVITE`).
  3. `c:answer/2` is called when Kamailio relays the SDP answer from
     the callee. `session.callee_local` is already allocated. Return
     the SDP that will be forwarded back to the caller in `200 OK`.
  4. `c:delete/2` is called when Kamailio tears down the call.

  All callbacks may return `{:error, reason, state}`, which causes
  ex_kamailio to reply to Kamailio with a Bencode error and skip any
  further pipeline setup for that command.
  """

  alias ExKamailio.Session

  @type state :: term()
  @type sdp :: String.t()
  @type reason :: term()

  @callback init(opts :: keyword()) :: {:ok, state()}

  @callback offer(Session.t(), state()) ::
              {:ok, sdp(), state()} | {:error, reason(), state()}

  @callback answer(Session.t(), state()) ::
              {:ok, sdp(), state()} | {:error, reason(), state()}

  @callback delete(Session.t(), state()) :: {:ok, state()}
end
