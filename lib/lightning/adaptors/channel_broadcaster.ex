defmodule Lightning.Adaptors.ChannelBroadcaster do
  @moduledoc """
  Fans adaptor changes out to connected sessions, coalescing bursts.

  Subscribes to `:source_topic`, the same topic
  `Lightning.Adaptors.Invalidator` listens on, and republishes one message
  of changed names to `:client_topic` at most once per `debounce_ms/0`
  window.

  The two topics have different audiences. The source topic keeps node
  caches coherent. The client topic tells `WorkflowChannel` subscribers
  which adaptors changed so they refetch, and nothing about what changed,
  so `:flush` never touches the cache or renders anything.
  """

  use GenServer

  @debounce_ms 250

  @doc """
  Leading-edge coalesce window in milliseconds. Tests derive receive
  timeouts from it.
  """
  @spec debounce_ms() :: pos_integer()
  def debounce_ms, do: @debounce_ms

  @doc """
  Start the ChannelBroadcaster linked to the calling process.

  Required opts:
    * `:name` - registered GenServer name.
    * `:source_topic` - PubSub topic to subscribe to.
    * `:client_topic` - PubSub topic to broadcast the changed names to.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    :ok =
      Phoenix.PubSub.subscribe(
        Lightning.PubSub,
        Keyword.fetch!(opts, :source_topic)
      )

    {:ok,
     %{
       client_topic: Keyword.fetch!(opts, :client_topic),
       timer: nil,
       names: MapSet.new()
     }}
  end

  @impl true
  # First message of a burst: arm the leading-edge timer.
  def handle_info({:changed, name, _source}, %{timer: nil} = state) do
    timer = Process.send_after(self(), :flush, @debounce_ms)
    {:noreply, %{state | timer: timer, names: MapSet.put(state.names, name)}}
  end

  def handle_info({:changed, name, _source}, state) do
    {:noreply, %{state | names: MapSet.put(state.names, name)}}
  end

  def handle_info(:flush, %{client_topic: topic, names: names} = state) do
    Phoenix.PubSub.broadcast(
      Lightning.PubSub,
      topic,
      %{
        event: "adaptors_updated",
        payload: %{names: Enum.sort(names)}
      }
    )

    {:noreply, %{state | timer: nil, names: MapSet.new()}}
  end
end
