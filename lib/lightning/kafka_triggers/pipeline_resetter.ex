defmodule Lightning.KafkaTriggers.PipelineResetter do
  use GenServer

  alias Lightning.KafkaTriggers

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    {:ok, opts}
  end

  @impl true
  def handle_info({:reset, trigger_id}, state) do
    IO.inspect(trigger_id, label: :reset_received)
    KafkaTriggers.reset_pipeline(trigger_id)

    {:noreply, state}
  end
end
