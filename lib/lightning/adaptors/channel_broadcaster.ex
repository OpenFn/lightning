defmodule Lightning.Adaptors.ChannelBroadcaster do
  @moduledoc """
  Burst-coalesced fan-out of adaptor changes to connected sessions.

  Subscribes to `:source_topic` (the cache-coherence topic shared with
  `Lightning.Adaptors.Invalidator`) and republishes a single envelope of
  changed names to `:client_topic` at most once per 250ms leading-edge
  window.

  Two-topic separation: the source topic is the cache-coherence audience;
  the client topic is the display-freshness audience (`WorkflowChannel`
  subscribers). This bridges them: the payload tells a session "these
  adaptors changed, go refetch" — not what changed about them, so
  `:flush` never has to touch the cache or render anything.
  """

  use GenServer

  @debounce_ms 250

  @doc """
  Leading-edge coalesce window in milliseconds.

  Exposed so integration tests can compute receive timeouts off the
  authoritative value rather than hard-coding a duplicate.
  """
  @spec debounce_ms() :: pos_integer()
  def debounce_ms, do: @debounce_ms

  @doc """
  Start the ChannelBroadcaster linked to the calling process.

  Required opts:
    * `:name` — registered GenServer name.
    * `:source_topic` — PubSub topic to subscribe to (cache-coherence).
    * `:client_topic` — PubSub topic to broadcast the changed names to.
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

  # Subsequent messages within the debounce window: accumulate, don't flush.
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
