defmodule KafkaSubscriber do
  require Logger

  @behaviour :brod_group_subscriber_v2
  def init(_arg, _arg2) do
    {:ok, []}
  end

  def handle_message(message, _state) do
    Logger.error(fn -> "KKKKKAAAAAAFFFFFKKKAAAAAA: " <> inspect(message) end)  
    {:ok, :commit, []}
  end
end
