defmodule Lightning.KafkaTriggers.MessageWorker do
  @moduledoc """
  Requests a message from the MessageServer and manages the state of the
  returned message.
  """
  use GenServer

  alias Lightning.KafkaTriggers.MessageHandling
  alias Lightning.KafkaTriggers.MessageServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    Process.send_after(self(), :request_message, 1000)

    {:ok, opts}
  end

  @impl true
  def handle_info(:request_message, state) do
    next_message_delay = Keyword.fetch!(state, :next_set_delay)
    no_message_delay = Keyword.fetch!(state, :no_set_delay)

    case MessageServer.next_message() do
      nil ->
        Process.send_after(self(), :request_message, no_message_delay)

      message_id ->
        MessageHandling.process_message_for(message_id)
        Process.send_after(self(), :request_message, next_message_delay)
    end

    {:noreply, state}
  end
end
