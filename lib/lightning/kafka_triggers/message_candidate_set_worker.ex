defmodule Lightning.KafkaTriggers.MessageCandidateSetWorker do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [])
  end

  @impl true
  def init(_opts) do
    {:ok, ["foo", "bar"]}
  end
end
