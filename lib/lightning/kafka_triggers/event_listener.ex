defmodule Lightning.KafkaTriggers.EventListener do
  use GenServer

  alias Lightning.KafkaTriggers
  alias Lightning.Workflows.Triggers.Events

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: :kafka_event_listener)
  end

  @impl true
  def init(_opts) do
    Events.subscribe_to_kafka_trigger_updated()

    {:ok, %{}}
  end

  @impl true
  def handle_info(%Events.KafkaTriggerUpdated{trigger_id: trigger_id}, state) do
    if supervisor = GenServer.whereis(:kafka_pipeline_supervisor) do
      supervisor |> KafkaTriggers.update_pipeline(trigger_id)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
