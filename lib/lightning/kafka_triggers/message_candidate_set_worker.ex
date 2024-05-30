defmodule Lightning.KafkaTriggers.MessageCandidateSetWorker do
  use GenServer

  alias Lightning.KafkaTriggers
  alias Lightning.KafkaTriggers.MessageCandidateSetServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [])
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :request_candidate_set, 100)

    {:ok, []}
  end

  @impl true
  def handle_info(:request_candidate_set, _state) do
    case MessageCandidateSetServer.next_candidate_set() do
      nil ->
        Process.send_after(self(), :request_candidate_set, 200)

      candidate_set ->
        KafkaTriggers.process_candidate_for(candidate_set)
        Process.send_after(self(), :request_candidate_set, 100)
    end

    {:noreply, [:called]}
  end
end
