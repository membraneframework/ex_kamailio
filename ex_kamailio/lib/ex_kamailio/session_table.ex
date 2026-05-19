defmodule ExKamailio.SessionTable do
  @moduledoc """
  ETS-backed store of active calls, keyed by SIP call-id.

  A periodic GC sweep drops sessions older than 30 minutes; the
  `c:ExKamailio.Handler.delete/2` callback should release any media
  resources tied to the session before the entry disappears.
  """

  use GenServer
  require Logger

  alias ExKamailio.Session

  @table :ex_kamailio_sessions
  @idx_from_tag :ex_kamailio_idx_from
  @idx_to_tag :ex_kamailio_idx_to

  @public_opts [
    :named_table,
    :public,
    :set,
    read_concurrency: true,
    write_concurrency: true
  ]

  # 30 minutes
  @max_age_seconds 30 * 60

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    :ets.new(@table, @public_opts)
    :ets.new(@idx_from_tag, @public_opts)
    :ets.new(@idx_to_tag, @public_opts)
    :timer.send_interval(:timer.minutes(5), :gc)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:gc, state) do
    now = System.monotonic_time(:second)

    :ets.foldl(
      fn {call_id, sess}, _acc ->
        touched = Map.get(sess, :touched_at, now)
        if now - touched > @max_age_seconds, do: delete(call_id)
        :ok
      end,
      :ok,
      @table
    )

    {:noreply, state}
  end

  @spec put(Session.t()) :: :ok
  def put(%Session{call_id: id} = session) when is_binary(id) do
    entry = {id, touch(session)}
    :ets.insert(@table, entry)
    if session.from_tag, do: :ets.insert(@idx_from_tag, {session.from_tag, id})
    if session.to_tag, do: :ets.insert(@idx_to_tag, {session.to_tag, id})
    :ok
  end

  @spec get(Session.call_id()) :: Session.t() | nil
  def get(call_id) when is_binary(call_id) do
    case :ets.lookup(@table, call_id) do
      [{^call_id, sess}] -> sess
      _ -> nil
    end
  end

  @spec delete(Session.call_id()) :: :ok
  def delete(call_id) when is_binary(call_id) do
    case :ets.take(@table, call_id) do
      [{^call_id, sess}] ->
        if sess.from_tag, do: :ets.match_delete(@idx_from_tag, {sess.from_tag, :_})
        if sess.to_tag, do: :ets.match_delete(@idx_to_tag, {sess.to_tag, :_})
        :ok

      _ ->
        :ok
    end
  end

  defp touch(%Session{} = sess) do
    Map.put(sess, :touched_at, System.monotonic_time(:second))
  end
end
