defmodule ExKamailio.Handler.Server do
  @moduledoc """
  One process per call: runs the user handler's callbacks and holds that call's
  `%ExKamailio.Session{}` (including the handler's own state) in its memory.

  Spawned under `ExKamailio.CallSupervisor` and registered by `call_id` in
  `ExKamailio.CallRegistry`, so an `offer`/`answer`/`delete` arriving on any
  pooled WebSocket connection routes to the same process. The registry entry is
  dropped automatically when the process stops.
  """

  use GenServer
  require Logger

  @registry ExKamailio.CallRegistry
  @supervisor ExKamailio.CallSupervisor

  # -- public API (used by ExKamailio.WebSocket) --

  @doc "Spawn (or look up) the call process for `call_id`, seeding handler state via `impl.init/1`."
  @spec start_call(String.t(), module(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_call(call_id, impl, impl_opts) do
    spec = %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [{call_id, impl, impl_opts}]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(@supervisor, spec) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  @spec call_offer(String.t(), ExKamailio.Session.t()) :: {:ok, binary()} | {:error, term()}
  def call_offer(call_id, session), do: request(call_id, {__MODULE__, :offer, session})

  @spec call_answer(String.t(), map()) :: {:ok, binary()} | {:error, term()}
  def call_answer(call_id, answer_fields), do: request(call_id, {__MODULE__, :answer, answer_fields})

  @spec call_delete(String.t()) :: :ok | {:error, term()}
  def call_delete(call_id), do: request(call_id, {__MODULE__, :delete})

  # A dead/absent call process becomes {:error, ...} instead of taking the
  # shared WebSocket caller down. The timeout must stay under Kamailio's
  # rtpengine_tout_ms (default 1000 ms) — a missed deadline gets the node
  # disabled for 60 s. The abort cast queues behind the slow callback, so the
  # call still tears down (handle_delete included) once that callback returns.
  defp request(call_id, request) do
    timeout = Application.get_env(:ex_kamailio, :handler_timeout, 800)
    GenServer.call(via(call_id), request, timeout)
  catch
    :exit, {:timeout, _} ->
      GenServer.cast(via(call_id), {__MODULE__, :abort})
      {:error, :timeout}

    :exit, {:noproc, _} ->
      {:error, :unknown}

    :exit, reason ->
      {:error, {:down, reason}}
  end

  def start_link({call_id, _impl, _opts} = arg) do
    GenServer.start_link(__MODULE__, arg, name: via(call_id))
  end

  defp via(call_id), do: {:via, Registry, {@registry, call_id}}

  # -- GenServer --

  @impl true
  def init({call_id, impl, impl_opts}) do
    {:ok, inner_state} = impl.init(impl_opts)

    state = %{
      call_id: call_id,
      impl: impl,
      inner_state: inner_state,
      session: nil,
      timeout: Application.get_env(:ex_kamailio, :call_timeout, :timer.minutes(30)),
      timer_ref: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({__MODULE__, :offer, session}, _from, state) do
    {:ok, sdp, inner_state} = state.impl.handle_offer(session, state.inner_state)
    state = arm_timer(%{state | session: session, inner_state: inner_state})
    {:reply, {:ok, wire(sdp)}, state}
  end

  # Kamailio retransmits 200 OK; replay the cached reply instead of re-invoking
  # the handler (which would spawn a second pipeline / re-bind ports).
  def handle_call(
        {__MODULE__, :answer, %{to_tag: to_tag}},
        _from,
        %{session: %{state: :answered, to_tag: to_tag, answer_reply_sdp: reply_sdp}} = state
      )
      when is_binary(reply_sdp) do
    {:reply, {:ok, reply_sdp}, state}
  end

  def handle_call({__MODULE__, :answer, fields}, _from, %{session: %{state: :offered}} = state) do
    session = %{
      state.session
      | state: :answered,
        to_tag: fields.to_tag,
        answerer_remote: fields.answerer_remote,
        answer_sdp: fields.answer_sdp
    }

    {:ok, sdp, inner_state} = state.impl.handle_answer(session, state.inner_state)
    wire_sdp = wire(sdp)
    session = %{session | answer_reply_sdp: wire_sdp}
    {:reply, {:ok, wire_sdp}, arm_timer(%{state | session: session, inner_state: inner_state})}
  end

  def handle_call({__MODULE__, :answer, _fields}, _from, state) do
    {:reply, {:error, :late}, state}
  end

  def handle_call({__MODULE__, :delete}, _from, state) do
    run_delete(state)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_cast({__MODULE__, :abort}, state) do
    Logger.warning("call #{state.call_id} missed the reply deadline; tearing down")
    run_delete(state)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({__MODULE__, :call_timeout}, state) do
    case state.impl.handle_timeout(state.session, state.inner_state) do
      {:stop, inner_state} ->
        state = %{state | inner_state: inner_state}
        Logger.warning("call #{state.call_id} idle-timed out; tearing down")
        run_delete(state)
        {:stop, :normal, state}

      {:noreply, inner_state} ->
        {:noreply, arm_timer(%{state | inner_state: inner_state})}
    end
  end

  def handle_info(message, state) do
    {:ok, inner_state} = state.impl.handle_info(message, state.session, state.inner_state)
    {:noreply, %{state | inner_state: inner_state}}
  end

  # -- internals --

  defp run_delete(%{session: nil}), do: :ok

  defp run_delete(state) do
    {:ok, _inner_state} = state.impl.handle_delete(state.session, state.inner_state)
    :ok
  end

  defp arm_timer(state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    %{state | timer_ref: Process.send_after(self(), {__MODULE__, :call_timeout}, state.timeout)}
  end

  defp wire(sdp) when is_binary(sdp), do: sdp
  defp wire(%ExSDP{} = sdp), do: to_string(sdp)
end
