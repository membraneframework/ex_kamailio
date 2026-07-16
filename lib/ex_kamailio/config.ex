defmodule ExKamailio.Config do
  @moduledoc false

  @default_ws_ip :loopback
  @default_ws_port 4003
  @default_call_handler ExKamailio.CallHandler.Default
  @default_idle_timeout :timer.minutes(30)
  @default_callback_timeout 800

  @spec call_registry() :: module()
  def call_registry, do: ExKamailio.CallRegistry

  @spec call_supervisor() :: module()
  def call_supervisor, do: ExKamailio.CallSupervisor

  @spec ws_ip() :: :inet.socket_address()
  def ws_ip, do: Application.get_env(:ex_kamailio, :ws_ip, @default_ws_ip)

  @spec ws_port() :: :inet.port_number()
  def ws_port, do: Application.get_env(:ex_kamailio, :ws_port, @default_ws_port)

  @spec call_handler() :: {module(), keyword()}
  def call_handler do
    case Application.get_env(:ex_kamailio, :call_handler, @default_call_handler) do
      {mod, opts} -> {mod, opts}
      mod when is_atom(mod) -> {mod, []}
    end
  end

  @spec default_call_handler() :: module()
  def default_call_handler, do: @default_call_handler

  @spec idle_timeout() :: timeout()
  def idle_timeout, do: Application.get_env(:ex_kamailio, :idle_timeout, @default_idle_timeout)

  @spec callback_timeout() :: timeout()
  def callback_timeout,
    do: Application.get_env(:ex_kamailio, :callback_timeout, @default_callback_timeout)
end
