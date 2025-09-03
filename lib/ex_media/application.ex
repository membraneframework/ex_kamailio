defmodule ExMedia.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    ws_port = Application.fetch_env!(:ex_media, :ws_port)
    children = [
      {ExMedia.PortPool, []},
      {ExMedia.SessionStore, []},
      {Bandit, plug: ExMedia.Router, scheme: :http, port: ws_port}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExMedia.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
