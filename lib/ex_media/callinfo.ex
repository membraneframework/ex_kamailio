defmodule ExMedia.CallInfo do
  @moduledoc """
  Struct for holding call information for every call
  """
  # One network endpoint (peer or local)
  defmodule Endpoint do
    @type ip4 :: {0..255, 0..255, 0..255, 0..255}
    @type ip6 :: {0..65535, 0..65535, 0..65535, 0..65535, 0..65535, 0..65535, 0..65535, 0..65535}
    @type ip :: ip4 | ip6 | String.t()

    @type t :: %__MODULE__{
            # peer/local IP (tuple or string)
            ip: ip,
            # RTP port
            rtp_port: 1..65535,
            rtcp_port: 1..65535 | nil
          }

    defstruct ip: {0, 0, 0, 0}, rtp_port: 0, rtcp_port: nil
  end

  # A single RTP pipeline (directional)
  defmodule Pipeline do
    @type direction :: :in | :out

    @type t :: %__MODULE__{
            dir: direction,
            # client or vendor side
            peer: Endpoint.t(),
            # your box’s bound IP/ports
            local: Endpoint.t()
          }

    defstruct dir: :in, peer: %Endpoint{}, local: %Endpoint{}
  end

  # Full call session identified by call_id
  defmodule Session do
    @type call_id :: String.t()

    @type t :: %__MODULE__{
            call_id: call_id,
            in: Pipeline.t(),
            out: Pipeline.t()
          }

    defstruct call_id: "",
              in: %Pipeline{dir: :in},
              out: %Pipeline{dir: :out}
  end

  @type store :: %{Session.call_id() => Session.t()}
end
