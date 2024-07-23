defmodule Lightning.KafkaTriggers.MessageCandidateSetSupervisor do
  @moduledoc """
  Starts the server and worker processes responsible for converting messages
  received from Kafka clusters. There are two sets of workers and servers. This
  is to accommodate messages that have keys (grouped into MessageCandidateSets) 
  ans those that do not, which are processed individually.
  """
  use Supervisor

  alias Lightning.KafkaTriggers.MessageCandidateSetServer
  alias Lightning.KafkaTriggers.MessageCandidateSetWorker
  alias Lightning.KafkaTriggers.MessageServer
  alias Lightning.KafkaTriggers.MessageWorker

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    number_of_workers = Keyword.get(opts, :number_of_workers, 1)

    mcs_children =
      generate_child_specs(:message_candidate_set, number_of_workers)

    message_children =
      generate_child_specs(:message, number_of_workers)

    Supervisor.init(mcs_children ++ message_children, strategy: :one_for_one)
  end

  def generate_worker_specs(number_of_workers) do
    no_set_delay =
      Application.get_env(:lightning, :kafka_triggers)[
        :no_message_candidate_set_delay_milliseconds
      ]

    next_set_delay =
      Application.get_env(:lightning, :kafka_triggers)[
        :next_message_candidate_set_delay_milliseconds
      ]

    0..(number_of_workers - 1)
    |> Enum.map(fn index ->
      {
        MessageCandidateSetWorker,
        [no_set_delay: no_set_delay, next_set_delay: next_set_delay]
      }
      |> Supervisor.child_spec(id: "mcs_worker_#{index}")
    end)
  end

  def generate_child_specs(:message_candidate_set, number_of_workers) do
    no_set_delay =
      Application.get_env(:lightning, :kafka_triggers)[
        :no_message_candidate_set_delay_milliseconds
      ]

    next_set_delay =
      Application.get_env(:lightning, :kafka_triggers)[
        :next_message_candidate_set_delay_milliseconds
      ]

    workers =
      0..(number_of_workers - 1)
      |> Enum.map(fn index ->
        {
          MessageCandidateSetWorker,
          [no_set_delay: no_set_delay, next_set_delay: next_set_delay]
        }
        |> Supervisor.child_spec(id: "mcs_worker_#{index}")
      end)

    [MessageCandidateSetServer] ++ workers
  end

  def generate_child_specs(:message, number_of_workers) do
    no_set_delay =
      Application.get_env(:lightning, :kafka_triggers)[
        :no_message_candidate_set_delay_milliseconds
      ]

    next_set_delay =
      Application.get_env(:lightning, :kafka_triggers)[
        :next_message_candidate_set_delay_milliseconds
      ]

    workers =
      0..(number_of_workers - 1)
      |> Enum.map(fn index ->
        {
          MessageWorker,
          [no_set_delay: no_set_delay, next_set_delay: next_set_delay]
        }
        |> Supervisor.child_spec(id: "message_worker_#{index}")
      end)

    [MessageServer] ++ workers
  end
end
