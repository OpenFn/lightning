defmodule Lightning.KafkaTriggerTestHelpers do

end

defmodule Lightning.KafkaTriggerTestHelpers.DummyServer do
  use GenServer

  def start_link(name) do
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  def init(:ok), do: {:ok, :ok}
end

defmodule Lightning.KafkaTriggerTestHelpers.DummyResetter do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: KafkaTriggerResetter)
  end

  @impl true
  def init(opts) do
    {:ok, opts}
  end

  @impl true
  def handle_info({:reset, trigger_id}, state) do
    Process.send(state[:notify], {:reset_received, trigger_id}, [])

    {:noreply, state}
  end
end
