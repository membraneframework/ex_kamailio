defmodule Sink.Pipeline do
  @moduledoc """
  Receives RTP at a UDP port and writes the depayloaded payload bytes to a
  file. Stands in for the "receiving peer" in the relay_handler test rig
  so the user can hear what arrives on the far side of the relay.

      Membrane.UDP.Source -> Membrane.RTP.Parser -> Membrane.File.Sink

  Output is raw codec payload concatenated back-to-back. With the
  default PCMA test fixture, play with:

      ffplay -f alaw -ar 8000 -ac 1 recordings/uas.alaw
  """

  use Membrane.Pipeline

  alias Membrane.{File, RTP, UDP}

  def start_link(opts) do
    Membrane.Pipeline.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def handle_init(_ctx, %{port: port, path: path}) do
    spec =
      child(:udp, %UDP.Source{local_port_no: port, local_address: :any})
      |> child(:parser, RTP.Parser)
      |> child(:file, %File.Sink{location: path})

    {[spec: spec], %{}}
  end
end
