defmodule Lightning.KafkaTriggers.MessageCandidateSetWorker do
  @moduledoc """
  Requests a message candidate set from the MessageCandidateSetServer and
  manages the state of the returned candidate set.
  """
  use GenServer

  alias Lightning.KafkaTriggers.MessageCandidateSetServer
  alias Lightning.KafkaTriggers.MessageHandling

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    Process.send_after(self(), :request_candidate_set, 1000)

    {:ok, opts}
  end

  @impl true
  def handle_info(:request_candidate_set, state) do
    next_set_delay = Keyword.fetch!(state, :next_set_delay)
    no_set_delay = Keyword.fetch!(state, :no_set_delay)

    case MessageCandidateSetServer.next_candidate_set() do
      nil ->
        Process.send_after(self(), :request_candidate_set, no_set_delay)

      candidate_set ->
        MessageHandling.process_candidate_for(candidate_set)
        Process.send_after(self(), :request_candidate_set, next_set_delay)
    end

    {:noreply, state}
  end
end
