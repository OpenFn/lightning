defmodule Lightning.KafkaTriggers.PipelineSupervisor do
  @moduledoc """
  Supervisor of the BroadwayKafka pipelines that are created for each enabled
  Kafka trigger.
  """
  use Supervisor

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, [], name: :kafka_pipeline_supervisor)
  end

  @impl true
  def init(_opts) do
    Supervisor.init([], strategy: :one_for_one)
  end
end
