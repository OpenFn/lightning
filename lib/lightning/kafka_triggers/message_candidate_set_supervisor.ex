defmodule Lightning.KafkaTriggers.MessageCandidateSetSupervisor do
  @moduledoc """
  Starts the server and worker processes responsible for converting messages
  received from Kafka clusters. The sole purpose of this is to ensure that
  messages with the same key (for a given cluster/topic configuration) are
  processed in the same order they were received.
  """
  use Supervisor

  alias Lightning.KafkaTriggers.MessageCandidateSetServer
  alias Lightning.KafkaTriggers.MessageCandidateSetWorker

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    number_of_workers = Keyword.get(opts, :number_of_workers, 1)

    children =
      [MessageCandidateSetServer] ++ generate_worker_specs(number_of_workers)

    Supervisor.init(children, strategy: :one_for_one)
  end

  def generate_worker_specs(number_of_workers) do
    no_set_delay =
      Lightning.Config.kafka_no_message_candidate_set_delay_milliseconds()

    next_set_delay =
      Lightning.Config.kafka_next_message_candidate_set_delay_milliseconds()

    0..(number_of_workers - 1)
    |> Enum.map(fn index ->
      {
        MessageCandidateSetWorker,
        [no_set_delay: no_set_delay, next_set_delay: next_set_delay]
      }
      |> Supervisor.child_spec(id: "mcs_worker_#{index}")
    end)
  end
end
