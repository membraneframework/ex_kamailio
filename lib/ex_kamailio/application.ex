defmodule ExKamailio.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    ws_port = Application.fetch_env!(:ex_kamailio, :ws_port)

    children = [
      ExKamailio.SessionTable,
      {Bandit, plug: ExKamailio.Router, scheme: :http, port: ws_port}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ExKamailio.Supervisor)
  end
end
