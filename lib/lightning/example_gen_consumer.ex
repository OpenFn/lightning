# stolen from kafka_ex docs
defmodule ExampleGenConsumer do
  use KafkaEx.GenConsumer

  alias KafkaEx.Protocol.Fetch.Message

  require Logger

  # note - messages are delivered in batches
  def handle_message_set(message_set, state) do
    for %Message{value: message} <- message_set do
      Logger.error(fn -> "KAFFFKAAAA message: " <> inspect(message) end)
    end
    {:async_commit, state}
  end
end
