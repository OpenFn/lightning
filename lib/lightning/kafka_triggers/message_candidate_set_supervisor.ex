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
      generate_child_specs(MessageCandidateSetServer, number_of_workers)

    message_children =
      generate_child_specs(MessageServer, number_of_workers)

    Supervisor.init(mcs_children ++ message_children, strategy: :one_for_one)
  end

  def generate_child_specs(server, number_of_workers) do
    {worker, id_prefix} =
      case server do
        MessageCandidateSetServer ->
          {MessageCandidateSetWorker, "mcs_worker"}

        MessageServer ->
          {MessageWorker, "message_worker"}
      end

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
          worker,
          [no_set_delay: no_set_delay, next_set_delay: next_set_delay]
        }
        |> Supervisor.child_spec(id: "#{id_prefix}_#{index}")
      end)

    [server | workers]
  end
end
