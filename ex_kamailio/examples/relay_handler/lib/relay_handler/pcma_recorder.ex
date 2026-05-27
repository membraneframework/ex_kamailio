defmodule RelayHandler.PcmaRecorder do
  @moduledoc """
  Inline Membrane filter that strips the 12-byte RTP header from each input
  buffer and appends the remaining PCMA payload to a file. Buffers pass
  through unchanged so the recorder can sit between two relay elements
  without breaking forwarding.

  The captured file is raw mono 8 kHz G.711 a-law — play with:

      ffplay -f alaw -ar 8000 -ac 1 capture.alaw
      sox -t al -r 8000 -c 1 capture.alaw capture.wav

  Assumes RTP packets have no CSRCs / extensions, which holds for typical
  softphone PCMA streams and for the SIPp scenarios in this example.
  """

  use Membrane.Filter

  def_options path: [spec: Path.t(), description: "File path to append PCMA payloads to."]

  def_input_pad :input, accepted_format: _any, flow_control: :auto
  def_output_pad :output, accepted_format: _any, flow_control: :auto

  @impl true
  def handle_init(_ctx, opts) do
    {[], %{path: opts.path, io: nil}}
  end

  @impl true
  def handle_setup(_ctx, state) do
    File.mkdir_p!(Path.dirname(state.path))
    {:ok, io} = :file.open(state.path, [:write, :raw, :binary])
    {[], %{state | io: io}}
  end

  @impl true
  def handle_buffer(:input, %Membrane.Buffer{payload: payload} = buffer, _ctx, state) do
    case payload do
      <<_header::12-bytes, pcma::binary>> -> :ok = :file.write(state.io, pcma)
      _ -> :ok
    end

    {[buffer: {:output, buffer}], state}
  end

  @impl true
  def handle_terminate_request(_ctx, %{io: nil} = state),
    do: {[terminate: :normal], state}

  def handle_terminate_request(_ctx, state) do
    :ok = :file.close(state.io)
    {[terminate: :normal], %{state | io: nil}}
  end
end
