defmodule Lightning.KafkaTriggers.MessageCandidateSetServer do
  use GenServer

  alias Lightning.KafkaTriggers

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def next_candidate_set do
    GenServer.call(__MODULE__, :next_candidate_set)
  end

  @impl true
  def init(_opts) do
    {:ok, []}
  end

  @impl true
  def handle_call(:next_candidate_set, _from, current_sets) do
    {candidate_set, remaining_sets} = pop_candidate(current_sets)

    {:reply, candidate_set, remaining_sets}
  end

  defp pop_candidate([]) do
    case KafkaTriggers.find_message_candidate_sets() do
      [candidate_set | remaining_sets] ->
        {candidate_set, remaining_sets}

      [] ->
        {nil, []}
    end
  end

  defp pop_candidate([candidate_set | remaining_sets]) do
    {candidate_set, remaining_sets}
  end
end
