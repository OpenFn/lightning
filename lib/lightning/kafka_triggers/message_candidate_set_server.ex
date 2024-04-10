defmodule Lightning.KafkaTriggers.MessageCandidateSetServer do
  @moduledoc """
  Server responsible for maintaining a list of message candidate sets that
  are provided to the worker processes.
  """
  use GenServer

  alias Lightning.KafkaTriggers.MessageHandling

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
    case MessageHandling.find_message_candidate_sets() do
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
