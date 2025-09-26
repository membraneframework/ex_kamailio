defmodule ExMedia.Membrane.Pipeline do
  alias ExMedia.Pipeline
  alias ExMedia.Utils
  require Logger

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

    case DynamicSupervisor.start_child(@sup, spec) do
      {:ok, sup_pid, pid} -> {:ok, sup_pid, pid}
      {:error, error} -> {:error, error}
    end
  end

  @spec delete(Pipeline.pipeline_id()) :: :ok
  def delete(pid) do
    DynamicSupervisor.terminate_child(@sup, pid)
  end

  @spec update(Pipeline.session(), pipeline_direction()) :: :ok
  def update(%{pipeline_pid: pid} = sess, :vendor) do
    Logger.debug(%{call: pid, vendor_side_data: sess})
    :ok = ShineMembranePipeline.setup_vendor_endpoint(
      pid,
      Utils.parse_ip!(elem(sess.answer.local, 0)),
      elem(sess.answer.local, 1),
      Utils.parse_ip!(elem(hd(sess.answer.remote), 0)),
      elem(hd(sess.answer.remote), 1)
    )
  end
  def update(%{pipeline_pid: pid} = sess, :client) do
    Logger.debug(%{call: pid, client_side_data: sess})
    :ok = ShineMembranePipeline.setup_client_endpoint(
      pid,
      Utils.parse_ip!(elem(sess.offer.local, 0)),
      elem(sess.offer.local, 1),
      Utils.parse_ip!(elem(hd(sess.offer.remote), 0)),
      elem(hd(sess.offer.remote), 1)
    )
  end
end
