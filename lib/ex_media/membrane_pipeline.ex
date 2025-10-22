defmodule ExMedia.Membrane.Pipeline do
  alias ExMedia.Pipeline
  alias ExMedia.Utils
  require Logger

  @type pipeline_direction :: :client | :vendor
  @registry ExMedia.PipelineRegistry
  @sup ExMedia.PipelineSupervisor

  # Use this wherever you need to name / find the pipeline process
  def via(id), do: {:via, Registry, {@registry, id}}

  # ——— Public API ———

  @spec create(Pipeline.pipeline_id()) :: :ok
  def create(pipeline_id) do
    spec = %{
      id: pipeline_id,
      start: {ShineMembranePipeline, :start_link, [name: via(pipeline_id)]},
      # don't restart finished calls
      restart: :temporary,
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

    Logger.debug("""
    Setting up vendor Membrane endpoint \
    (local ip: #{inspect(Utils.parse_ip!(elem(sess.vendor_side.local, 0)))} \
    port: #{inspect(elem(sess.vendor_side.local, 1))} <-> \
    remote ip: #{inspect(Utils.parse_ip!(elem(hd(sess.vendor_side.remote), 0)))} \
    port: #{inspect(elem(hd(sess.vendor_side.remote), 1))})
    """)

    :ok =
      ShineMembranePipeline.setup_vendor_endpoint(
        pid,
        Utils.parse_ip!(elem(sess.vendor_side.local, 0)),
        elem(sess.vendor_side.local, 1),
        Utils.parse_ip!(elem(hd(sess.vendor_side.remote), 0)),
        elem(hd(sess.vendor_side.remote), 1)
      )
  end

  def update(%{pipeline_pid: pid} = sess, :client) do
    Logger.debug(%{call: pid, client_side_data: sess})

    Logger.debug("""
    Setting up client Membrane endpoint \
    (local ip: #{inspect(Utils.parse_ip!(elem(sess.client_side.local, 0)))} \
    port: #{inspect(elem(sess.client_side.local, 1))} <-> \
    remote ip: #{inspect(Utils.parse_ip!(elem(hd(sess.client_side.remote), 0)))} \
    port: #{inspect(elem(hd(sess.client_side.remote), 1))})
    """)

    :ok =
      ShineMembranePipeline.setup_client_endpoint(
        pid,
        Utils.parse_ip!(elem(sess.client_side.local, 0)),
        elem(sess.client_side.local, 1),
        Utils.parse_ip!(elem(hd(sess.client_side.remote), 0)),
        elem(hd(sess.client_side.remote), 1)
      )
  end
end
