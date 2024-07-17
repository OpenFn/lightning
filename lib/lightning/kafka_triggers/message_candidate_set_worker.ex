defmodule Lightning.KafkaTriggers.MessageCandidateSetWorker do
  @moduledoc """
  Requests a message candidate set from the MessageCandidateSetServer and
  manages the state of the returned candidate set.
  """
  use GenServer

  alias Lightning.KafkaTriggers.MessageCandidateSetServer
  alias Lightning.KafkaTriggers.MessageHandling

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [])
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :request_candidate_set, 1000)

    {:ok, []}
  end

  @impl true
  def handle_info(:request_candidate_set, _state) do
    case MessageCandidateSetServer.next_candidate_set() do
      nil ->
        Process.send_after(self(), :request_candidate_set, 2000)

      candidate_set ->
        MessageHandling.process_candidate_for(candidate_set)
        Process.send_after(self(), :request_candidate_set, 1000)
    end

    {:noreply, [:called]}
  end
end
