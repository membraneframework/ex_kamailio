defmodule ExKamailio.Session do
  @moduledoc """
  State of a single call, threaded through `ExKamailio.Handler` callbacks.

  - `call_id` / `from_tag` / `to_tag` — SIP identifiers forwarded by Kamailio.
  - `state` — lifecycle state: `:offered` after the offer has been processed,
    `:answered` once the answer has come back.
  - `offerer_remote` / `answerer_remote` — endpoints parsed from the offer and
    the answer SDP respectively, for the handler's convenience. May still be
    behind NAT; symmetric-RTP latching happens at the media layer.
  - `offer_sdp` / `answer_sdp` — parsed `%ExSDP{}` structs from each party.
  - `answer_reply_sdp` — the SDP text we sent back to Kamailio on the first
    answer. Cached so retransmitted answer commands can be served
    idempotently without re-invoking the handler.
  - `handler_state` — the user handler's per-call state, held by the call's own
    process (`ExKamailio.Handler.Server`).
  """

  alias ExKamailio.Endpoint

  @type call_id :: String.t()
  @type lifecycle :: :offered | :answered

  @type t :: %__MODULE__{
          call_id: call_id(),
          from_tag: String.t() | nil,
          to_tag: String.t() | nil,
          state: lifecycle(),
          offerer_remote: Endpoint.t() | nil,
          answerer_remote: Endpoint.t() | nil,
          offer_sdp: ExSDP.t() | nil,
          answer_sdp: ExSDP.t() | nil,
          answer_reply_sdp: String.t() | nil,
          handler_state: term()
        }

  defstruct [
    :call_id,
    :from_tag,
    :to_tag,
    :state,
    :offerer_remote,
    :answerer_remote,
    :offer_sdp,
    :answer_sdp,
    :answer_reply_sdp,
    :handler_state
  ]
end
