defmodule ExKamailio.Application do
  @moduledoc false
  use Application

  alias ExKamailio.ConstantsAndConfig

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: ConstantsAndConfig.call_registry()},
      {DynamicSupervisor, name: ConstantsAndConfig.call_supervisor(), strategy: :one_for_one},
      {Bandit, plug: ExKamailio.Router, scheme: :http, port: ConstantsAndConfig.ws_port()}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ExKamailio.Supervisor)
  end
end
