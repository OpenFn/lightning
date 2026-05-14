defmodule Lightning.Adaptors.Scheduler do
  @moduledoc """
  Cluster-singleton GenServer that periodically refreshes the active
  source's ledger via the configured strategy, persists through
  `Lightning.Adaptors.Repo`, and broadcasts `{:changed, name, source}`.

  Wrapped by `HighlanderPG` in production so only one node in the cluster
  runs the scheduler at a time. Peer nodes react via
  `Lightning.Adaptors.Invalidator` and `Lightning.Adaptors.ChannelBroadcaster`.

  Smart-init timing: the first tick is scheduled at
  `max(0, last_checked_at + interval - now)` to avoid double-refreshing
  shortly after a deploy. An empty table or an overdue schedule fires
  immediately (`delay = 0`). Interval `0` disables scheduling entirely.
  """

  use GenServer

  alias Lightning.Adaptors.Config
  alias Lightning.Adaptors.Repo, as: AdaptorsRepo
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  require Logger

  @doc """
  Start the Scheduler for the given supervisor instance.

  Required opts: `:name`, `:sup`, `:lock_key`, `:cache`, `:tasks`,
  `:source_topic`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    _ = Keyword.fetch!(opts, :sup)
    _ = Keyword.fetch!(opts, :lock_key)
    _ = Keyword.fetch!(opts, :cache)
    _ = Keyword.fetch!(opts, :tasks)
    _ = Keyword.fetch!(opts, :source_topic)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Trigger an immediate refresh tick on the leader node.

  Returns `{:error, :not_leader}` when HighlanderPG routes to a
  non-leader (returned by the HighlanderPG wrapper, not this GenServer).
  """
  @spec refresh_now(atom()) :: :ok | {:error, :not_leader}
  def refresh_now(scheduler_name) do
    GenServer.call(scheduler_name, :refresh_now)
  end

  @doc """
  Force a single-adaptor refresh, bypassing the diff. 30-second timeout.

  Returns `{:error, :not_leader}` from HighlanderPG on non-leaders;
  `{:error, :not_found}` or `{:error, term()}` from a failed strategy fetch.
  """
  @spec refresh_package(atom(), String.t()) ::
          :ok | {:error, :not_leader | :not_found | term()}
  def refresh_package(scheduler_name, name) do
    GenServer.call(scheduler_name, {:refresh_package, name}, 30_000)
  end

  @impl true
  def init(opts) do
    sup = Keyword.fetch!(opts, :sup)
    source_topic = Keyword.fetch!(opts, :source_topic)
    cache = Keyword.fetch!(opts, :cache)
    tasks = Keyword.fetch!(opts, :tasks)

    source = AdaptorsSupervisor.source(sup)
    interval_ms = Config.refresh_interval()

    if interval_ms > 0 do
      delay =
        time_until_next_ms(AdaptorsRepo.max_checked_at(source), interval_ms)

      Process.send_after(self(), :tick, delay)
    end

    {:ok,
     %{
       sup: sup,
       source: source,
       interval_ms: interval_ms,
       source_topic: source_topic,
       cache: cache,
       tasks: tasks
     }}
  end

  @impl true
  def handle_info(:tick, state) do
    if state.interval_ms > 0 do
      Process.send_after(self(), :tick, state.interval_ms)
    end

    Task.Supervisor.start_child(state.tasks, fn -> do_refresh(state) end)

    {:noreply, state}
  end

  @impl true
  def handle_call(:refresh_now, _from, state) do
    send(self(), :tick)
    {:reply, :ok, state}
  end

  def handle_call({:refresh_package, name}, _from, state) do
    strategy = AdaptorsSupervisor.strategy(state.sup)
    result = force_refresh_one(strategy, name, state)
    {:reply, result, state}
  end

  defp do_refresh(state) do
    strategy = AdaptorsSupervisor.strategy(state.sup)

    case strategy.list_adaptors() do
      {:ok, upstream} ->
        existing_by_name =
          state.source
          |> AdaptorsRepo.list_adaptors()
          |> Map.new(fn a -> {a.name, a.latest_version} end)

        Enum.each(upstream, fn %{name: name, latest_version: version} ->
          refresh_one(strategy, name, version, existing_by_name, state)
        end)

      {:error, reason} ->
        Logger.warning("Scheduler: list_adaptors failed: #{inspect(reason)}")
    end
  end

  defp refresh_one(strategy, name, version, existing_by_name, state) do
    if Map.get(existing_by_name, name) == version do
      AdaptorsRepo.touch_checked_at(name, state.source)
    else
      case strategy.fetch_adaptor(name) do
        {:ok, record} ->
          record_with_source = Map.put(record, :source, state.source)
          {:ok, _} = AdaptorsRepo.upsert_adaptor(record_with_source)

          Phoenix.PubSub.broadcast(
            Lightning.PubSub,
            state.source_topic,
            {:changed, name, state.source}
          )

        {:error, reason} ->
          Logger.warning(
            "Scheduler: fetch_adaptor(#{name}) failed: #{inspect(reason)}"
          )
      end
    end
  end

  defp force_refresh_one(strategy, name, state) do
    case strategy.fetch_adaptor(name) do
      {:ok, record} ->
        record_with_source = Map.put(record, :source, state.source)
        {:ok, _} = AdaptorsRepo.upsert_adaptor(record_with_source)

        Phoenix.PubSub.broadcast(
          Lightning.PubSub,
          state.source_topic,
          {:changed, name, state.source}
        )

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp time_until_next_ms(nil, _interval_ms), do: 0

  defp time_until_next_ms(%DateTime{} = last, interval_ms) do
    next = DateTime.add(last, interval_ms, :millisecond)
    diff = DateTime.diff(next, DateTime.utc_now(), :millisecond)
    max(0, diff)
  end
end
