# lib/ex_media/session_table.ex
defmodule ExMedia.SessionTable do
  @moduledoc """
  Owns ETS tables for RTP sessions.
  """

  use GenServer
  require Logger

  # primary by call-id
  @table :exmedia_sessions
  # optional secondary index
  @idx_from_tag :exmedia_idx_from
  @idx_to_tag :exmedia_idx_to

  @public_opts [
    :named_table,
    :public,
    :set,
    read_concurrency: true,
    write_concurrency: true
  ]

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    Logger.info("Creating ETS for media sessions")
    :ets.new(@table, @public_opts)
    :ets.new(@idx_from_tag, @public_opts)
    :ets.new(@idx_to_tag, @public_opts)

    # optional: periodic GC of stale sessions
    :timer.send_interval(:timer.minutes(5), :gc)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:gc, state) do
    now = System.monotonic_time(:second)
    # delete sessions older than N seconds (example: 30 min)
    max_age = 30 * 60
    # Walk table & delete stale rows
    :ets.foldl(
      fn {call_id, sess}, _acc ->
        touched = Map.get(sess, :touched_at, now)
        if now - touched > max_age, do: delete(call_id)
        :ok
      end,
      :ok,
      @table
    )

    {:noreply, state}
  end

  # ---------- PUBLIC API (fast wrappers around ETS) ----------

  def table, do: @table

  def put_session(%{call_id: call_id} = session) when is_binary(call_id) do
    # upsert primary
    :ets.insert(@table, {call_id, touch(session)})
    # maintain secondary indices
    if from = session[:from_tag], do: :ets.insert(@idx_from_tag, {from, call_id})
    if to = session[:to_tag], do: :ets.insert(@idx_to_tag, {to, call_id})
    :ok
  end

  def get_session(call_id) when is_binary(call_id) do
    case :ets.lookup(@table, call_id) do
      [{^call_id, sess}] -> sess
      _ -> nil
    end
  end

  def update_session(call_id, fun) when is_function(fun, 1) do
    case get_session(call_id) do
      nil ->
        :error

      sess ->
        new = touch(fun.(sess))
        IO.inspect(new)
        :ets.insert(@table, {call_id, new})
        :ok
    end
  end

  def delete(call_id) do
    case :ets.take(@table, call_id) do
      [{^call_id, sess}] ->
        if from = sess[:from_tag], do: :ets.match_delete(@idx_from_tag, {from, :_})
        if to = sess[:to_tag], do: :ets.match_delete(@idx_to_tag, {to, :_})
        :ok

      _ ->
        :ok
    end
  end

  def lookup_by_from_tag(tag) do
    for {^tag, call_id} <- :ets.lookup(@idx_from_tag, tag),
        [{^call_id, sess}] <- [:ets.lookup(@table, call_id)],
        do: sess
  end

  def lookup_by_to_tag(tag) do
    for {^tag, call_id} <- :ets.lookup(@idx_to_tag, tag),
        [{^call_id, sess}] <- [:ets.lookup(@table, call_id)],
        do: sess
  end

  defp touch(sess), do: Map.put(sess, :touched_at, System.monotonic_time(:second))
end
