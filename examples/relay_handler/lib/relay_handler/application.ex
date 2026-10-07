defmodule RelayHandler.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [RelayHandler.PortPool]
    Supervisor.start_link(children, strategy: :one_for_one, name: RelayHandler.Supervisor)
  end
end
