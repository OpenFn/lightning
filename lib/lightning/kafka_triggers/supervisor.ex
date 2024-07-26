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

    number_of_workers =
      Lightning.Config.kafka_number_of_message_candidate_set_workers()

    children =
      if enabled do
        [
          %{
            id: Lightning.KafkaTriggers.MessageCandidateSetSupervisor,
            start: {
              Lightning.KafkaTriggers.MessageCandidateSetSupervisor,
              :start_link,
              [[number_of_workers: number_of_workers]]
            },
            type: :supervisor
          },
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
