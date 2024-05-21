defmodule Lightning.KafkaTriggers.MessageCandidateSetWorker do
  use GenServer

  alias Lightning.KafkaTriggers

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [])
  end

  @impl true
  def init(_opts) do
    KafkaTriggers.send_after(self(), :request_candidate_set, 100)

    {:ok, []}
  end
end
