defmodule Lightning.KafkaTriggers.MessageServer do
  @moduledoc """
  Server responsible for maintaining a list of messages with nil keys that
  are provided to the worker processes.
  """
  use GenServer

  alias Lightning.KafkaTriggers.MessageHandling

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def next_message do
    GenServer.call(__MODULE__, :next_message)
  end

  @impl true
  def init(_opts) do
    {:ok, []}
  end

  @impl true
  def handle_call(:next_message, _from, current_messages) do
    {message, remaining_messages} = pop_message(current_messages)

    {:reply, message, remaining_messages}
  end

  defp pop_message([]) do
    case MessageHandling.find_nil_key_message_ids() do
      [] -> {nil, []}
      result -> pop_message(result)
    end
  end

  defp pop_message([message | remaining_messages]) do
    {message, remaining_messages}
  end
end
