defmodule ExKamailio.Session do
  @moduledoc """
  State of a single call, threaded through `ExKamailio.Handler` callbacks:
  the SIP identifiers plus every SDP that crossed the wire, in both
  directions. Each field is nil until the call reaches that point.

  - `call_id` / `from_tag` / `to_tag` — SIP identifiers forwarded by Kamailio.
  - `from_offerer_sdp` / `from_answerer_sdp` — `%ExSDP{}` received from that
    peer.
  - `to_answerer_sdp` / `to_offerer_sdp` — `%ExSDP{}` the handler returned,
    forwarded by Kamailio to that peer.
  """

  @type call_id :: String.t()

  @type t :: %__MODULE__{
          call_id: call_id(),
          from_tag: String.t() | nil,
          to_tag: String.t() | nil,
          from_offerer_sdp: ExSDP.t() | nil,
          to_answerer_sdp: ExSDP.t() | nil,
          from_answerer_sdp: ExSDP.t() | nil,
          to_offerer_sdp: ExSDP.t() | nil
        }

  defstruct [
    :call_id,
    :from_tag,
    :to_tag,
    :from_offerer_sdp,
    :to_answerer_sdp,
    :from_answerer_sdp,
    :to_offerer_sdp
  ]
end
