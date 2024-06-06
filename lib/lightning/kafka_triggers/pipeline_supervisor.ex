defmodule Lightning.KafkaTriggers.PipelineSupervisor do
  use Supervisor

  alias Lightning.KafkaTriggers.PipelineWorker

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, [], name: :kafka_pipeline_supervisor)
  end

  @impl true
  def init(_opts) do
    run_kafka_trigger_supervisors = Application.get_env(
      :lightning,
      :kafka_triggers
    )[:run_supervisors]

    if run_kafka_trigger_supervisors do
      # TODO Find an alternative way to do this that is testable or live
      # with the blindspot?
      Oban.insert(Lightning.Oban, PipelineWorker.new(%{}, schedule_in: 10))
    end

    Supervisor.init([], strategy: :one_for_one)
  end
end
