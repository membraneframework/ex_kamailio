defmodule ExKamailio.Endpoint do
  @moduledoc """
  A single network endpoint — IP and RTP/RTCP ports.

  Used to describe both the local endpoint allocated by ex_kamailio and the
  remote endpoint parsed from a SIP party's SDP.
  """

  @type ip :: :inet.ip_address() | String.t()

  @type t :: %__MODULE__{
          ip: ip(),
          rtp_port: 1..65_535,
          rtcp_port: 1..65_535 | nil
        }

  defstruct [:ip, :rtp_port, :rtcp_port]
end
