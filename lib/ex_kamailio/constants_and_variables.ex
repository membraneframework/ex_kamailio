defmodule ExKamailio.ConstantsAndVariables do
  @moduledoc false

  def call_registry, do: ExKamailio.CallRegistry

  def call_supervisor, do: ExKamailio.CallSupervisor

  def ws_port, do: Application.fetch_env!(:ex_kamailio, :ws_port)

  def call_handler do
    case Application.fetch_env!(:ex_kamailio, :call_handler) do
      {mod, opts} -> {mod, opts}
      mod when is_atom(mod) -> {mod, []}
    end
  end

  def idle_timeout, do: Application.get_env(:ex_kamailio, :idle_timeout, :timer.minutes(30))

  def callback_timeout,
    do: Application.get_env(:ex_kamailio, :callback_timeout, 800)
end
