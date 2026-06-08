defmodule Sink.Application do
  @moduledoc false
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    port = String.to_integer(System.get_env("SINK_PORT") || "6000")
    path = System.get_env("SINK_OUTPUT") || "/recordings/uas.alaw"

    Logger.info("[sink] capturing UDP/#{port} to #{path}")

    Supervisor.start_link(
      [{Sink.Pipeline, %{port: port, path: path}}],
      strategy: :one_for_one,
      name: Sink.Supervisor
    )
  end
end
