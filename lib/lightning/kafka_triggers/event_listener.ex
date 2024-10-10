defmodule Lightning.KafkaTriggers.EventListener do
  @moduledoc """
  Listens for events related to Kafka triggers and updates the affected pipeline
  process by enabling, reloading or disabling it.
  """
  use GenServer

  alias Lightning.KafkaTriggers
  alias Lightning.Workflows.Triggers.Events
  alias Lightning.Workflows.Triggers.Events.KafkaTriggerNotificationSent
  alias Lightning.Workflows.Triggers.Events.KafkaTriggerUpdated

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: :kafka_event_listener)
  end

  @impl true
  def init(_opts) do
    Events.subscribe_to_kafka_trigger_updated()

    {:ok, %{}}
  end

  @impl true
  def handle_info(%KafkaTriggerUpdated{trigger_id: trigger_id}, state) do
    if supervisor = GenServer.whereis(:kafka_pipeline_supervisor) do
      supervisor |> KafkaTriggers.update_pipeline(trigger_id)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(%KafkaTriggerNotificationSent{} = notification, state) do
    %{trigger_id: trigger_id, sent_at: sent_at} = notification

    :persistent_term.put(
      KafkaTriggers.failure_notification_tracking_key(trigger_id),
      sent_at
    )

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
