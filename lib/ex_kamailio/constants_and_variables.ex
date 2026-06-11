defmodule ExKamailio.ConstantsAndVariables do
  @moduledoc """
  Single source for the process names and application environment the rest of
  ex_kamailio reads.
  """

  def call_registry, do: ExKamailio.CallRegistry

  def call_supervisor, do: ExKamailio.CallSupervisor

  def ws_port, do: Application.fetch_env!(:ex_kamailio, :ws_port)

  @doc "The configured handler, normalized to `{module, init_opts}`."
  def call_handler do
    case Application.fetch_env!(:ex_kamailio, :call_handler) do
      {mod, opts} -> {mod, opts}
      mod when is_atom(mod) -> {mod, []}
    end
  end

  def call_timeout, do: Application.get_env(:ex_kamailio, :call_timeout, :timer.minutes(30))

  def rtpengine_command_timeout,
    do: Application.get_env(:ex_kamailio, :rtpengine_command_timeout, 800)
end
