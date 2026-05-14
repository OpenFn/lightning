defmodule Lightning.Adaptors.ChannelBroadcaster do
  @moduledoc """
  Burst-coalesced fan-out of adaptor changes to connected sessions.

  Subscribes to `:source_topic` (the cache-coherence topic shared with
  `Lightning.Adaptors.Invalidator`) and republishes a single pre-rendered
  envelope to `:client_topic` at most once per 250ms leading-edge window.

  Two-topic separation: the source topic is the cache-coherence audience;
  the client topic is the display-freshness audience (`WorkflowChannel`
  subscribers). This bridges them: `Lightning.Adaptors.packages/1` is
  rendered once per burst and fanned out by PubSub rather than once per
  session (§6.5c).

  No within-callback fan-out in `:flush` — `Phoenix.PubSub.broadcast/3`
  is a single call that reaches all subscribers in one hop (§10 #19).
  """

  use GenServer

  @debounce_ms 250

  @doc """
  Start the ChannelBroadcaster linked to the calling process.

  Required opts:
    * `:name` — registered GenServer name.
    * `:source_topic` — PubSub topic to subscribe to (cache-coherence).
    * `:client_topic` — PubSub topic to broadcast the rendered envelope to.
    * `:sup` — supervisor instance name; forwarded to
      `Lightning.Adaptors.packages/1` for per-instance isolation.
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
       sup: Keyword.fetch!(opts, :sup),
       timer: nil
     }}
  end

  @impl true
  # First message of a burst: arm the leading-edge timer.
  def handle_info({:changed, _name, _source}, %{timer: nil} = state) do
    timer = Process.send_after(self(), :flush, @debounce_ms)
    {:noreply, %{state | timer: timer}}
  end

  # Subsequent messages within the debounce window: drop on the floor.
  def handle_info({:changed, _name, _source}, state) do
    {:noreply, state}
  end

  def handle_info(:flush, %{client_topic: topic, sup: sup} = state) do
    case Lightning.Adaptors.packages(sup) do
      {:ok, pkgs} ->
        Phoenix.PubSub.broadcast(
          Lightning.PubSub,
          topic,
          %{event: "adaptors_updated", payload: %{adaptors: pkgs}}
        )

      {:error, _} ->
        :ok
    end

    {:noreply, %{state | timer: nil}}
  end
end
