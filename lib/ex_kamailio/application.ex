defmodule ExKamailio.Application do
  @moduledoc false
  use Application

  alias ExKamailio.Config

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Config.call_registry()},
      {DynamicSupervisor, name: Config.call_supervisor(), strategy: :one_for_one},
      {Bandit, plug: ExKamailio.Router, scheme: :http, port: Config.ws_port()}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ExKamailio.Supervisor)
  end
end
