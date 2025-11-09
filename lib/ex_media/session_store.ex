defmodule ExMedia.SessionStore do
  @moduledoc "ETS store for RTP sessions, keyed by call_id."
  use GenServer
  alias ExMedia.CallInfo.Session

  @table :rtp_sessions

  # ——— Public API ———

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec put(Session.t()) :: :ok
  def put(%Session{call_id: id} = s) do
    :ets.insert(@table, {id, s})
    :ok
  end

  @spec get(Session.call_id()) :: {:ok, Session.t()} | :error
  def get(id) do
    case :ets.lookup(@table, id) do
      [{^id, s}] -> {:ok, s}
      [] -> :error
    end
  end

  @spec delete(Session.call_id()) :: :ok
  def delete(id) do
    :ets.delete(@table, id)
    :ok
  end

  @spec upsert(Session.call_id(), (Session.t() | nil -> Session.t())) :: :ok
  def upsert(id, fun) when is_function(fun, 1) do
    # Simple, safe pattern: read current, compute new, insert
    current =
      case :ets.lookup(@table, id) do
        [{^id, s}] -> s
        [] -> nil
      end

    :ets.insert(@table, {id, fun.(current)})
    :ok
  end

  @spec all() :: [Session.t()]
  def all, do: :ets.tab2list(@table) |> Enum.map(fn {_id, s} -> s end)

  # ——— GenServer ———

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :set,
      :named_table,
      # anyone can read; only owner writes
      :protected,
      read_concurrency: true,
      write_concurrency: true
      # , :compressed               # optional: saves memory, slower CPU
    ])

    {:ok, %{}}
  end
end
