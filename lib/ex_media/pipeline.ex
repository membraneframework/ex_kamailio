# lib/shine/pipeline_behavior.ex
defmodule ExMedia.Pipeline do
  @moduledoc """
  Behaviour for runtime-managed media pipelines.

  A pipeline is identified by `pipeline_id` (e.g. call-id).
  """

  @type pipeline_id :: term()
  @type start_opts :: map()
  @type update_opts :: map()
  @type stop_reason :: :normal | :shutdown | :crash | atom() | {atom(), term()}
  @type error_reason :: term()
  @type pipeline_data :: map()

  @callback create(pipeline_id(), start_opts()) ::
              {:ok, pid()} | {:error, error_reason()}

  @callback update(pipeline_id(), update_opts()) ::
              :ok | {:ok, term()} | {:error, error_reason()}

  @callback stop(pipeline_id(), stop_reason()) ::
              :ok | {:error, error_reason()}

  @callback get(pipeline_id()) ::
              {:ok, pipeline_data()} | {:error, error_reason()}

end
