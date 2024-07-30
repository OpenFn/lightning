defmodule Lightning.KafkaTriggers.MessageCandidateSetSupervisor do
  @moduledoc """
  Starts the server and worker processes responsible for converting messages
  received from Kafka clusters. There are two sets of workers and servers. This
  is to accommodate messages that have keys (grouped into MessageCandidateSets)
  and those that do not, which are processed individually.
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
    # TODO: move the config upwards (to the supervisor), and pass in the exact
    # config values needed by the children
    config = Keyword.get(opts, :config, Lightning.Config)

    child_opts = [
      number_of_workers: number_of_workers,
      no_message_candidate_set_delay_milliseconds:
        config.kafka_no_message_candidate_set_delay_milliseconds(),
      next_message_candidate_set_delay_milliseconds:
        config.kafka_next_message_candidate_set_delay_milliseconds()
    ]

    mcs_children =
      generate_child_specs(MessageCandidateSetServer, child_opts)

    message_children =
      generate_child_specs(MessageServer, child_opts)

    Supervisor.init(mcs_children ++ message_children, strategy: :one_for_one)
  end

  def generate_child_specs(server, opts) do
    no_set_delay =
      opts |> Keyword.fetch!(:no_message_candidate_set_delay_milliseconds)

    next_set_delay =
      opts |> Keyword.fetch!(:next_message_candidate_set_delay_milliseconds)

    number_of_workers = opts |> Keyword.fetch!(:number_of_workers)

    {worker, id_prefix} =
      case server do
        MessageCandidateSetServer ->
          {MessageCandidateSetWorker, "mcs_worker"}

        MessageServer ->
          {MessageWorker, "message_worker"}
      end

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
