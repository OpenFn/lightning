defmodule Lightning.Workflows.Triggers.Events do
  @moduledoc """
  Responsible for the publishing of and subscription to trigger-related events.
  """
  defmodule KafkaTriggerUpdated do
    @moduledoc false
    defstruct trigger_id: nil
  end

  defmodule KafkaTriggerNotificationSent do
    @moduledoc false
    defstruct trigger_id: nil, sent_at: nil
  end

  def kafka_trigger_updated(trigger_id) do
    Lightning.broadcast(
      kafka_trigger_updated_topic(),
      %KafkaTriggerUpdated{trigger_id: trigger_id}
    )
  end

  def subscribe_to_kafka_trigger_updated do
    Lightning.subscribe(kafka_trigger_updated_topic())
  end

  def kafka_trigger_updated_topic, do: "kafka_trigger_updated"

  def kafka_trigger_notification_sent(trigger_id, sent_at) do
    Lightning.broadcast(
      kafka_trigger_updated_topic(),
      %KafkaTriggerNotificationSent{trigger_id: trigger_id, sent_at: sent_at}
    )
  end
end
