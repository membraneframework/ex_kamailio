defmodule ExKamailio.Handler.Server do
  @moduledoc """
  One process per call: runs the user handler's callbacks and holds that call's
  `%ExKamailio.Session{}` (including the handler's own state) in its memory.

  Spawned under `ExKamailio.CallSupervisor` and registered by `call_id` in
  `ExKamailio.CallRegistry`, so an `offer`/`answer`/`delete` arriving on any
  pooled WebSocket connection routes to the same process. The registry entry is
  dropped automatically when the process stops.

  `ExKamailio.WebSocket` talks to this module only through `start_call/3` and
  `call_offer/2` / `call_answer/2` / `call_delete/1`, which turn a dead call
  process into `{:error, ...}` instead of propagating the exit into the
  transport.
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

  # The catch clauses turn a dead/absent call process into {:error, ...} rather
  # than an exit in the caller (the shared WebSocket process), so one bad call
  # can't take the transport down with it.

  @spec call_offer(String.t(), ExKamailio.Session.t()) :: {:ok, binary()} | {:error, term()}
  def call_offer(call_id, session) do
    GenServer.call(via(call_id), {:offer, session})
  catch
    :exit, {:noproc, _} -> {:error, :unknown}
    :exit, reason -> {:error, {:down, reason}}
  end

  @spec call_answer(String.t(), map()) :: {:ok, binary()} | {:error, term()}
  def call_answer(call_id, answer_fields) do
    GenServer.call(via(call_id), {:answer, answer_fields})
  catch
    :exit, {:noproc, _} -> {:error, :unknown}
    :exit, reason -> {:error, {:down, reason}}
  end

  @spec call_delete(String.t()) :: :ok | {:error, term()}
  def call_delete(call_id) do
    GenServer.call(via(call_id), :delete)
  catch
    :exit, {:noproc, _} -> {:error, :unknown}
    :exit, reason -> {:error, {:down, reason}}
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
  def handle_call({:offer, session}, _from, state) do
    case state.impl.offer(session, state.inner_state) do
      {:ok, sdp, inner_state} ->
        state = arm_timer(%{state | session: session, inner_state: inner_state})
        {:reply, {:ok, wire(sdp)}, state}

      {:error, reason, inner_state} ->
        {:stop, :normal, {:error, reason}, %{state | inner_state: inner_state}}
    end
  end

  # Kamailio retransmits 200 OK; rtpengine_answer fires again. Replay the cached
  # reply instead of re-invoking the handler (which would spawn a second
  # pipeline / re-bind ports).
  def handle_call(
        {:answer, %{to_tag: to_tag}},
        _from,
        %{session: %{state: :answered, to_tag: to_tag, answer_reply_sdp: reply_sdp}} = state
      )
      when is_binary(reply_sdp) do
    {:reply, {:ok, reply_sdp}, state}
  end

  def handle_call({:answer, fields}, _from, %{session: %{state: :offered}} = state) do
    session = %{
      state.session
      | state: :answered,
        to_tag: fields.to_tag,
        callee_remote: fields.callee_remote,
        answer_sdp: fields.answer_sdp
    }

    case state.impl.answer(session, state.inner_state) do
      {:ok, sdp, inner_state} ->
        wire_sdp = wire(sdp)
        session = %{session | answer_reply_sdp: wire_sdp}

        {:reply, {:ok, wire_sdp},
         arm_timer(%{state | session: session, inner_state: inner_state})}

      {:error, reason, inner_state} ->
        # Don't commit the :answered transition — the call stays :offered so a
        # retried answer (or a delete) still works.
        {:reply, {:error, reason}, %{state | inner_state: inner_state}}
    end
  end

  def handle_call({:answer, _fields}, _from, state) do
    {:reply, {:error, :late}, state}
  end

  def handle_call(:delete, _from, state) do
    safe_delete(state)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info(:call_timeout, state) do
    case state.impl.handle_timeout(state.session, state.inner_state) do
      {:stop, inner_state} ->
        state = %{state | inner_state: inner_state}
        Logger.warning("call #{state.call_id} idle-timed out; tearing down")
        safe_delete(state)
        {:stop, :normal, state}

      {:noreply, inner_state} ->
        {:noreply, arm_timer(%{state | inner_state: inner_state})}
    end
  end

  def handle_info(message, state) do
    case state.impl.handle_info(message, state.session, state.inner_state) do
      {:ok, inner_state} -> {:noreply, %{state | inner_state: inner_state}}
      {:error, reason, inner_state} -> {:stop, reason, %{state | inner_state: inner_state}}
    end
  end

  # -- internals --

  # Best-effort teardown: a crashing delete still lets us reply and stop, so a
  # buggy handler can't wedge the call process.
  defp safe_delete(%{session: nil}), do: :ok

  defp safe_delete(state) do
    state.impl.delete(state.session, state.inner_state)
    :ok
  rescue
    e -> Logger.error("handler delete crashed: #{Exception.message(e)}")
  catch
    kind, reason -> Logger.error("handler delete #{inspect(kind)}: #{inspect(reason)}")
  end

  defp arm_timer(state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    %{state | timer_ref: Process.send_after(self(), :call_timeout, state.timeout)}
  end

  defp wire(sdp) when is_binary(sdp), do: sdp
  defp wire(%ExSDP{} = sdp), do: to_string(sdp)
end
