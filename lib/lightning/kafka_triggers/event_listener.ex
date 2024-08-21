defmodule Lightning.KafkaTriggers.EventListener do
  @moduledoc """
  Listens for events related to Kafka triggers and updates the affected pipeline
  process by enabling, reloading or disabling it.
  """
  use GenServer

  alias Lightning.KafkaTriggers
  alias Lightning.Workflows.Triggers.Events

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: :kafka_event_listener)
  end

  @impl true
  def init(_opts) do
    Events.subscribe_to_kafka_trigger_events()

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
  def handle_info(%Events.KafkaTriggerPersistenceFailure{} = event, state) do
    %{trigger_id: trigger_id, timestamp: timestamp} = event

    if supervisor = GenServer.whereis(:kafka_pipeline_supervisor) do
      supervisor |> KafkaTriggers.rollback_pipeline(trigger_id, timestamp)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_event, state) do
    {:noreply, state}
  end
end
