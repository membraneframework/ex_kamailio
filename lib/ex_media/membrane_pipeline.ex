defmodule ExMedia.Membrane.Pipeline do
  alias ExMedia.Pipeline

  @type pipeline_direction :: :client | :vendor
  @registry ExMedia.PipelineRegistry
  @sup      ExMedia.PipelineSupervisor

  # Use this wherever you need to name / find the pipeline process
  def via(id), do: {:via, Registry, {@registry, id}}

  # ——— Public API ———

  @spec create(Pipeline.pipeline_id()) :: :ok
  def create(pipeline_id) do
    spec = %{
      id: pipeline_id,
      start: {ShineMembranePipeline, :start_link, [name: via(pipeline_id)]} ,
      restart: :temporary,   # don't restart finished calls
      shutdown: 5_000,
      type: :worker
    }

    case DynamicSupervisor.start_child(ExMedia.PipelineSupervisor, spec) do
      {:ok, sup_pid, pid} -> {:ok, sup_pid, pid}
      #{:error, {:already_started, pid}} -> {:ok, pid}
      {:error, error} -> {:error, error}
    end
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

  @spec update(Pipeline.session(), pipeline_direction()) :: :ok
  def update(%{pipeline_pid: pid} = sess, :vendor) do

    ## Simple, safe pattern: read current, compute new, insert
    #current = case :ets.lookup(@table, id) do
    #  [{^id, s}] -> s
    #  [] -> nil
    #end
    #:ets.insert(@table, {id, fun.(current)})
    :ok
  end
  def update(%{pipeline_pid: pid} = sess, :client) do
    :ok = ShineMembranePipeline.setup_client_endpoint(
      pid,
      elem(sess.offer.local, 0),
      elem(sess.offer.local, 1),
      elem(hd(sess.offer.remote), 0),
      elem(hd(sess.offer.remote), 1)
    )
    ## Simple, safe pattern: read current, compute new, insert
    #current = case :ets.lookup(@table, id) do
    #  [{^id, s}] -> s
    #  [] -> nil
    #end
    #:ets.insert(@table, {id, fun.(current)})
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
      :protected,                 # anyone can read; only owner writes
      read_concurrency: true,
      write_concurrency: true
      # , :compressed               # optional: saves memory, slower CPU
    ])
  create{:ok, %{}}
  end
end
