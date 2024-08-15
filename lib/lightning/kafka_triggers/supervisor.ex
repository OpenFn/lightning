defmodule Lightning.KafkaTriggers.Supervisor do
  @moduledoc """
  Starts all the processes needed to pull data from Kafka clusters and then
  generate work orders based on the messages received.
  """
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    enabled = Lightning.Config.kafka_triggers_enabled?()

    children =
      if enabled do
        [
          {
            Lightning.KafkaTriggers.PipelineSupervisor,
            type: :supervisor
          },
          Lightning.KafkaTriggers.EventListener,
          {Task, &Lightning.KafkaTriggers.start_triggers/0}
        ]
      else
        []
      end

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
