defmodule ExKamailio.Handler.GenServer do
  @moduledoc false
  use GenServer

  @impl true
  def init(opts) do
    %{impl: impl, impl_init_opts: impl_init_opts} = Map.new(opts)
    {:ok, inner_state} = impl.init(impl_init_opts)
    {:ok, %{impl: impl, inner_state: inner_state}}
  end

  @impl true
  def handle_call({__MODULE__, callback, session}, _from, state)
      when callback in [:offer, :answer] do
    case apply(state.impl, callback, [session, state.inner_state]) do
      {:ok, sdp, inner_state} ->
        {:reply, {:ok, sdp}, %{state | inner_state: inner_state}}

      {:error, reason, inner_state} ->
        {:stop, reason, %{state | inner_state: inner_state}}
    end
  end

  @impl true
  def handle_info(message, state) do
    case state.impl.handle_info(message, state.inner_state) do
      {:ok, inner_state} ->
        {:noreply, %{state | inner_state: inner_state}}

      {:error, reason, inner_state} ->
        {:stop, reason, %{state | inner_state: inner_state}}
    end
  end
end
