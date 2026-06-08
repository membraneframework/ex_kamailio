defmodule ExKamailio.Session do
  @moduledoc """
  State of a single call, threaded through `ExKamailio.Handler` callbacks.

  - `call_id` / `from_tag` / `to_tag` — SIP identifiers forwarded by Kamailio.
  - `state` — lifecycle state: `:offered` after the offer has been processed,
    `:answered` once the answer has come back.
  - `caller_local` / `callee_local` — endpoints allocated by ex_kamailio for
    each leg of the call. These are the addresses Kamailio rewrites the SDP
    to point at, so RTP from each party arrives at our box.
  - `caller_remote` / `callee_remote` — endpoints learned from each party's
    SDP (caller's from the offer, callee's from the answer). May still be
    behind NAT; symmetric-RTP latching happens at the media layer.
  - `offer_sdp` / `answer_sdp` — parsed `%ExSDP{}` structs from each party.
  - `answer_reply_sdp` — the SDP text we sent back to Kamailio on the first
    answer. Cached so retransmitted answer commands can be served
    idempotently without re-invoking the handler.
  - `handler_state` — the user handler's per-call state. Stored here (not in
    the WebSocket process) because Kamailio's rtpengine client pools several
    WebSocket connections and spreads one call's offer/answer/delete across
    them; keying the state by `call_id` in the shared table is what lets the
    `delete` callback see what `answer` stored.
  """

  alias ExKamailio.Endpoint

  @type call_id :: String.t()
  @type lifecycle :: :offered | :answered

  @type t :: %__MODULE__{
          call_id: call_id(),
          from_tag: String.t() | nil,
          to_tag: String.t() | nil,
          state: lifecycle(),
          caller_local: Endpoint.t() | nil,
          callee_local: Endpoint.t() | nil,
          caller_remote: Endpoint.t() | nil,
          callee_remote: Endpoint.t() | nil,
          offer_sdp: ExSDP.t() | nil,
          answer_sdp: ExSDP.t() | nil,
          answer_reply_sdp: String.t() | nil,
          handler_state: term(),
          touched_at: integer() | nil
        }

  defstruct [
    :call_id,
    :from_tag,
    :to_tag,
    :state,
    :caller_local,
    :callee_local,
    :caller_remote,
    :callee_remote,
    :offer_sdp,
    :answer_sdp,
    :answer_reply_sdp,
    :handler_state,
    :touched_at
  ]
end
