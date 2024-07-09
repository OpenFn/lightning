defmodule Lightning.KafkaTriggers.MessageCandidateSet do
  @moduledoc """
  A message candidate set is a representative of a group of TriggerKafkaMessages
  that belog to the same trigger and have an identical ttopic and key.
  """
  defstruct [:trigger_id, :topic, :key]
end
