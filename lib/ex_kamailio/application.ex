defmodule ExKamailio.Application do
  @moduledoc false
  use Application

  alias ExKamailio.ConstantsAndVariables

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: ConstantsAndVariables.call_registry()},
      {DynamicSupervisor, name: ConstantsAndVariables.call_supervisor(), strategy: :one_for_one},
      {Bandit, plug: ExKamailio.Router, scheme: :http, port: ConstantsAndVariables.ws_port()}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ExKamailio.Supervisor)
  end
end
