defmodule Lightning.KafkaTriggers.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(__init_arg) do
    run_kafka_trigger_supervisors =
      Application.get_env(:lightning, :kafka_triggers)[:run_supervisors]

    children =
      if run_kafka_trigger_supervisors do
        [
          {
            Lightning.KafkaTriggers.MessageCandidateSetSupervisor,
            type: :supervisor
          },
          {
            Lightning.KafkaTriggers.PipelineSupervisor,
            type: :supervisor
          },
          {Task, Lightning.KafkaTriggers.start_triggers() / 0},
          Lightning.KafkaTriggers.EventListener
        ]
      else
        []
      end

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
