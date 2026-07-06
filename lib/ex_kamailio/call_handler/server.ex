defmodule ExKamailio.CallHandler.Server do
  @moduledoc false
  # One process per call: runs the handler's callbacks and holds the call's
  # `%ExKamailio.Session{}` (plus the handler's own state).
  #
  # Registered by `call_id` in `ExKamailio.CallRegistry`, so a command arriving on
  # any pooled WebSocket connection routes to the same process; the registry entry
  # drops when the process stops.
  #
  # TODO: prompt teardown of crashed calls (rtpengine `--b2b-url` analogue).
  # Right now information about crash of a call handler process does not
  # reach Kamailio. Possible fix: load the `dialog` module + `jsonrpcs` in .cfg,
  # monitor the call process, and POST `dlg.terminate_dlg` on abnormal exit.

  use GenServer
  require Logger

  alias ExKamailio.{ConstantsAndConfig, Session}

  @type call_id :: String.t()

  @type call_spec :: %{
          call_id: call_id(),
          from_tag: String.t() | nil,
          impl: module(),
          impl_opts: keyword()
        }

  @spec start_call(call_spec()) :: {:ok, pid()} | {:error, term()}
  def start_call(%{call_id: _call_id} = call_spec) do
    spec = %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [call_spec]},
      restart: :temporary
    }

    ConstantsAndConfig.call_supervisor()
    |> DynamicSupervisor.start_child(spec)
    |> case do
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  @spec call_offer(call_id(), Session.t()) :: {:ok, binary()} | {:error, term()}
  def call_offer(call_id, session),
    do: request(call_id, {__MODULE__, :offer, session})

  @spec call_answer(call_id(), map()) :: {:ok, binary()} | {:error, term()}
  def call_answer(call_id, answer_fields),
    do: request(call_id, {__MODULE__, :answer, answer_fields})

  @spec call_delete(call_id()) :: :ok | {:error, term()}
  def call_delete(call_id),
    do: request(call_id, {__MODULE__, :delete})

  defp request(call_id, request) do
    GenServer.call(via(call_id), request, ConstantsAndConfig.callback_timeout())
  catch
    :exit, {:timeout, _call_details} ->
      GenServer.cast(via(call_id), {__MODULE__, :abort})
      {:error, :timeout}

    :exit, {:noproc, _call_details} ->
      {:error, :unknown}

    :exit, reason ->
      {:error, {:down, reason}}
  end

  @spec start_link(call_spec()) :: GenServer.on_start()
  def start_link(%{call_id: call_id} = call_spec) do
    GenServer.start_link(__MODULE__, call_spec, name: via(call_id))
  end

  defp via(call_id), do: {:via, Registry, {ConstantsAndConfig.call_registry(), call_id}}

  @impl true
  def init(%{call_id: call_id, from_tag: from_tag, impl: impl, impl_opts: impl_opts}) do
    {:ok, inner_state} = impl.init(%Session{call_id: call_id, from_tag: from_tag}, impl_opts)

    state = %{
      call_id: call_id,
      impl: impl,
      inner_state: inner_state,
      session: nil,
      timeout: ConstantsAndConfig.idle_timeout(),
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
  def handle_info({__MODULE__, :idle}, state) do
    case state.impl.handle_idle(state.session, state.inner_state) do
      {:stop, inner_state} ->
        state = %{state | inner_state: inner_state}
        Logger.warning("call #{state.call_id} idle-timed out; tearing down")
        run_delete(state)
        {:stop, :normal, state}

      {:ok, inner_state} ->
        {:noreply, arm_timer(%{state | inner_state: inner_state})}
    end
  end

  def handle_info(message, state) do
    {:ok, inner_state} = state.impl.handle_info(message, state.session, state.inner_state)
    {:noreply, %{state | inner_state: inner_state}}
  end

  defp run_delete(%{session: nil}), do: :ok

  defp run_delete(state) do
    :ok = state.impl.handle_delete(state.session, state.inner_state)
  end

  defp arm_timer(state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    %{state | timer_ref: Process.send_after(self(), {__MODULE__, :idle}, state.timeout)}
  end
end
