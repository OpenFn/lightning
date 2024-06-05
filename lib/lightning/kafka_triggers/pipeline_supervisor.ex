defmodule Lightning.KafkaTriggers.PipelineSupervisor do
  use Supervisor

  alias Lightning.KafkaTriggers.PipelineWorker

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, [], name: :kafka_pipeline_supervisor)
  end

  @impl true
  def init(_opts) do
    # TODO Not tested
    if Mix.env != :test do
      Oban.insert(Lightning.Oban, PipelineWorker.new(%{}, schedule_in: 10))
    end

    Supervisor.init([], strategy: :one_for_one)
  end
end
