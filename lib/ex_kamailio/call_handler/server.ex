defmodule ExKamailio.CallHandler.Server do
  @moduledoc false
  # One process per call: runs the handler's callbacks and holds the call's
  # `%ExKamailio.Session{}` (plus the handler's own state).
  #
  # Registered by `call_id` in `ExKamailio.CallRegistry`, so a command arriving on
  # any pooled WebSocket connection routes to the same process; the registry entry
  # drops when the process stops.

  use GenServer
  require Logger

  alias ExKamailio.ConstantsAndVariables

  # -- public API (used by ExKamailio.WebSocket) --

  # Spawn (or look up) the call process for `call_id`, seeding handler state via `impl.init/1`.
  @spec start_call(String.t(), module(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_call(call_id, impl, impl_opts) do
    spec = %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [{call_id, impl, impl_opts}]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(ConstantsAndVariables.call_supervisor(), spec) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  @spec call_offer(String.t(), ExKamailio.Session.t()) :: {:ok, binary()} | {:error, term()}
  def call_offer(call_id, session), do: request(call_id, {__MODULE__, :offer, session})

  @spec call_answer(String.t(), map()) :: {:ok, binary()} | {:error, term()}
  def call_answer(call_id, answer_fields),
    do: request(call_id, {__MODULE__, :answer, answer_fields})

  @spec call_delete(String.t()) :: :ok | {:error, term()}
  def call_delete(call_id), do: request(call_id, {__MODULE__, :delete})

  defp request(call_id, request) do
    GenServer.call(via(call_id), request, ConstantsAndVariables.rtpengine_command_timeout())
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

  defp via(call_id), do: {:via, Registry, {ConstantsAndVariables.call_registry(), call_id}}

  # -- GenServer --

  # TODO: prompt teardown of crashed calls (rtpengine `--b2b-url` analogue).
  # A raise in handle_info/3 or handle_timeout/2 kills this process silently — the
  # registry entry drops, but the request/response ng protocol leaves Kamailio's
  # SIP dialog up with dead media until someone hangs up. Mirror rtpengine: load
  # the `dialog` module + `jsonrpcs`, monitor the call process, and POST
  # `dlg.terminate_dlg` on abnormal exit.

  @impl true
  def init({call_id, impl, impl_opts}) do
    {:ok, inner_state} = impl.init(impl_opts)

    state = %{
      call_id: call_id,
      impl: impl,
      inner_state: inner_state,
      session: nil,
      timeout: ConstantsAndVariables.call_timeout(),
      timer_ref: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call(
        {__MODULE__, :offer, _session},
        _from,
        %{session: %{to_answerer_sdp: %ExSDP{} = sdp}} = state
      ) do
    {:reply, {:ok, to_string(sdp)}, state}
  end

  def handle_call({__MODULE__, :offer, session}, _from, state) do
    {:ok, %ExSDP{} = sdp, inner_state} =
      state.impl.handle_offer(session.from_offerer_sdp, session, state.inner_state)

    session = %{session | to_answerer_sdp: sdp}
    state = %{state | session: session, inner_state: inner_state}
    {:reply, {:ok, to_string(sdp)}, arm_timer(state)}
  end

  def handle_call(
        {__MODULE__, :answer, %{to_tag: to_tag}},
        _from,
        %{session: %{to_tag: to_tag, to_offerer_sdp: %ExSDP{} = sdp}} = state
      ) do
    {:reply, {:ok, to_string(sdp)}, state}
  end

  def handle_call(
        {__MODULE__, :answer, fields},
        _from,
        %{session: %{to_offerer_sdp: nil} = session} = state
      ) do
    session = %{session | to_tag: fields.to_tag, from_answerer_sdp: fields.from_answerer_sdp}

    {:ok, %ExSDP{} = sdp, inner_state} =
      state.impl.handle_answer(session.from_answerer_sdp, session, state.inner_state)

    session = %{session | to_offerer_sdp: sdp}
    state = %{state | session: session, inner_state: inner_state}
    {:reply, {:ok, to_string(sdp)}, arm_timer(state)}
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
end
