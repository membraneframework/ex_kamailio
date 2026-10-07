defmodule RelayHandler.Endpoint do
  @moduledoc """
  A single network endpoint — IP and RTP/RTCP ports.

  Internal bookkeeping for the relay: describes both the local socket this
  handler binds and the remote endpoint parsed from a peer's SDP.
  """

  @type ip :: :inet.ip_address() | String.t()

  @type t :: %__MODULE__{
          ip: ip(),
          rtp_port: 1..65_535,
          rtcp_port: 1..65_535 | nil
        }

  defstruct [:ip, :rtp_port, :rtcp_port]
end
