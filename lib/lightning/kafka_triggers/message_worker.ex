defmodule Lightning.KafkaTriggers.MessageWorker do
  @moduledoc """
  Requests a message candidate set from the MessageCandidateSetServer and
  manages the state of the returned candidate set.
  """
  use GenServer

  alias Lightning.KafkaTriggers.MessageServer
  alias Lightning.KafkaTriggers.MessageHandling

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
  #   next_set_delay = Keyword.fetch!(state, :next_set_delay)
    no_message_delay = Keyword.fetch!(state, :no_set_delay)

    case MessageServer.next_message() do
      nil ->
        Process.send_after(self(), :request_message, no_message_delay)

      message_id ->
        MessageHandling.process_message_for(message_id)
  #       Process.send_after(self(), :request_candidate_set, next_set_delay)
    end

    {:noreply, state}
  end
end
