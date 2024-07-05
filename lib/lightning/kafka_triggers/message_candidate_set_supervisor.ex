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

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, [])
  end

  @impl true
  def init(_opts) do
    children = [
      MessageCandidateSetServer,
      MessageCandidateSetWorker
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
