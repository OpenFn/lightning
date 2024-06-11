defmodule Lightning.KafkaTriggers.MessageCandidateSetSupervisor do
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
