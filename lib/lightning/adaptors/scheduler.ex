defmodule Lightning.Adaptors.Scheduler do
  @moduledoc """
  Cluster-singleton GenServer that periodically refreshes the active
  source's ledger via the configured strategy, persists through
  `Lightning.Adaptors.Repo`, and broadcasts `{:changed, name, source}`.

  Wrapped by `HighlanderPG` so only one node in the cluster runs the
  Scheduler at a time. The inner GenServer registers under
  `{:global, Lightning.Adaptors.Supervisor.global_scheduler_name(name)}`,
  so callers on any node reach the leader transparently via Erlang
  distribution. Peer nodes react to refreshes via
  `Lightning.Adaptors.Invalidator` and
  `Lightning.Adaptors.ChannelBroadcaster`.

  Smart-init timing: the first tick is scheduled at
  `max(0, last_checked_at + interval - now)` to avoid double-refreshing
  shortly after a deploy. An empty table or an overdue schedule fires
  immediately (`delay = 0`). Interval `0` disables scheduling entirely.

  ## Two-pipeline refresh

  A tick runs two parallel pipelines under the per-instance
  `Task.Supervisor`:

    * **Pipeline A** — `strategy.fetch_icons/0` for every adaptor.
    * **Pipeline B** — `strategy.list_adaptors/0` followed by a bounded
      per-adaptor fan-out (`async_stream_nolink`) calling
      `strategy.fetch_adaptor/1` only for names whose `latest_version`
      changed since the last tick.

  Once both pipelines complete the join step merges the icons map into
  each fetched record, writes the icon bytes to disk via
  `Lightning.Adaptors.IconCache.write!/5`, and upserts each adaptor in
  one go. `refresh_package/2` deliberately bypasses the icon pipeline —
  on-demand single-package refreshes do not refetch icons.
  """

  use GenServer

  alias Lightning.Adaptors.Config
  alias Lightning.Adaptors.IconCache
  alias Lightning.Adaptors.Repo, as: AdaptorsRepo
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  require Logger

  @fetch_max_concurrency 8
  @icons_task_timeout :timer.seconds(60)

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
  Trigger an immediate refresh tick.

  Routes via `:global` to the leader-held GenServer.
  """
  @spec refresh_now(GenServer.server()) :: :ok | {:error, term()}
  def refresh_now(scheduler_name) do
    GenServer.call(scheduler_name, :refresh_now)
  end

  @doc """
  Force a single-adaptor refresh, bypassing the diff. 30-second timeout.

  Returns `{:error, :not_found}` or `{:error, term()}` from a failed
  strategy fetch.
  """
  @spec refresh_package(GenServer.server(), String.t()) ::
          :ok | {:error, :not_found | term()}
  def refresh_package(scheduler_name, name) do
    GenServer.call(scheduler_name, {:refresh_package, name}, 30_000)
  end

  @doc """
  Refresh icons only, against every source-scoped adaptor row.

  Runs `strategy.fetch_icons/0` and re-applies any shape whose `sha256`
  differs from what is on the row. Adaptor metadata and version rows
  are not touched. Returns `{:ok, %{updated: n, unchanged: m}}` on
  success or `{:error, reason}` if the bulk fetch fails.
  """
  @spec refresh_icons(GenServer.server()) ::
          {:ok, %{updated: non_neg_integer(), unchanged: non_neg_integer()}}
          | {:error, term()}
  def refresh_icons(scheduler_name) do
    GenServer.call(scheduler_name, :refresh_icons, 120_000)
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

      Logger.info(
        "Adaptors[#{source}]: scheduler started interval=#{interval_ms}ms next_tick_in=#{delay}ms"
      )
    else
      Logger.info("Adaptors[#{source}]: scheduler started interval=0 (disabled)")
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
    Logger.info("Adaptors[#{state.source}]: refresh_now requested")
    send(self(), :tick)
    {:reply, :ok, state}
  end

  def handle_call({:refresh_package, name}, _from, state) do
    Logger.info("Adaptors[#{state.source}]: refresh_package(#{name}) requested")

    strategy = AdaptorsSupervisor.strategy(state.sup)
    result = force_refresh_one(strategy, name, state)
    {:reply, result, state}
  end

  def handle_call(:refresh_icons, _from, state) do
    Logger.info("Adaptors[#{state.source}]: refresh_icons requested")
    strategy = AdaptorsSupervisor.strategy(state.sup)

    case strategy.fetch_icons() do
      {:ok, icons} ->
        existing = AdaptorsRepo.list_adaptors(state.source)
        result = reapply_icons(existing, icons, state)

        Logger.info(
          "Adaptors[#{state.source}]: refresh_icons done " <>
            "rows=#{length(existing)} icons=#{map_size(icons)} " <>
            "updated=#{result.updated} unchanged=#{result.unchanged}"
        )

        {:reply, {:ok, result}, state}

      {:error, reason} ->
        Logger.warning(
          "Adaptors[#{state.source}]: refresh_icons strategy fetch failed: #{inspect(reason)}"
        )

        {:reply, {:error, reason}, state}
    end
  end

  defp do_refresh(state) do
    started_at = System.monotonic_time(:millisecond)
    strategy = AdaptorsSupervisor.strategy(state.sup)

    icons_task =
      Task.Supervisor.async_nolink(state.tasks, fn ->
        strategy.fetch_icons()
      end)

    case strategy.list_adaptors() do
      {:ok, upstream} ->
        existing_by_name =
          state.source
          |> AdaptorsRepo.list_adaptors()
          |> Map.new(fn a -> {a.name, a.latest_version} end)

        {fetched, changed, errors} =
          state.tasks
          |> Task.Supervisor.async_stream_nolink(
            upstream,
            &fetch_if_changed(strategy, &1, existing_by_name, state),
            max_concurrency: @fetch_max_concurrency,
            ordered: false,
            on_timeout: :kill_task
          )
          |> Enum.reduce({[], 0, 0}, fn
            {:ok, {:fetched, record}}, {acc, c, e} -> {[record | acc], c + 1, e}
            {:ok, :touched}, {acc, c, e} -> {acc, c, e}
            {:ok, {:error, _reason}}, {acc, c, e} -> {acc, c, e + 1}
            {:exit, _reason}, {acc, c, e} -> {acc, c, e + 1}
          end)

        icons = await_icons(icons_task)

        persisted =
          fetched
          |> Enum.map(fn record -> persist_with_icons(record, icons, state) end)
          |> Enum.count(&(&1 == :ok))

        healed = heal_missing_icons(icons, state)

        listed = length(upstream)
        touched = listed - changed - errors
        duration_ms = System.monotonic_time(:millisecond) - started_at

        Logger.info(
          "Adaptors[#{state.source}]: refresh tick listed=#{listed} " <>
            "changed=#{changed} touched=#{touched} fetched=#{persisted} " <>
            "icons=#{map_size(icons)} healed=#{healed} " <>
            "errors=#{errors} duration=#{duration_ms}ms"
        )

      {:error, reason} ->
        Logger.warning("Scheduler: list_adaptors failed: #{inspect(reason)}")
        _ = await_icons(icons_task)
        duration_ms = System.monotonic_time(:millisecond) - started_at

        Logger.info(
          "Adaptors[#{state.source}]: refresh tick listed=0 changed=0 " <>
            "touched=0 fetched=0 icons=0 errors=1 duration=#{duration_ms}ms"
        )

        :ok
    end
  end

  defp fetch_if_changed(
         strategy,
         %{name: name, latest_version: version},
         existing_by_name,
         state
       ) do
    if Map.get(existing_by_name, name) == version do
      AdaptorsRepo.touch_checked_at(name, state.source)
      :touched
    else
      case strategy.fetch_adaptor(name) do
        {:ok, record} ->
          Logger.debug(
            "Adaptors[#{state.source}]: fetched #{name}@#{record.version}"
          )

          {:fetched, record}

        {:error, reason} ->
          Logger.warning(
            "Scheduler: fetch_adaptor(#{name}) failed: #{inspect(reason)}"
          )

          {:error, reason}
      end
    end
  end

  defp await_icons(task) do
    case Task.yield(task, @icons_task_timeout) || Task.shutdown(task) do
      {:ok, {:ok, map}} when is_map(map) ->
        map

      {:ok, {:error, reason}} ->
        Logger.warning(
          "Scheduler: fetch_icons failed: #{inspect(reason)} — persisting records without icons"
        )

        %{}

      {:exit, reason} ->
        Logger.warning(
          "Scheduler: fetch_icons crashed: #{inspect(reason)} — persisting records without icons"
        )

        %{}

      nil ->
        Logger.warning(
          "Scheduler: fetch_icons timed out — persisting records without icons"
        )

        %{}
    end
  end

  defp persist_with_icons(record, icons, state) do
    name = record.name
    package_icons = Map.get(icons, name, %{})

    record_with_icons =
      record
      |> Map.put(:source, state.source)
      |> merge_icon(:square, package_icons, state.source)
      |> merge_icon(:rectangle, package_icons, state.source)

    try do
      {:ok, _} = AdaptorsRepo.upsert_adaptor(record_with_icons)

      Phoenix.PubSub.broadcast(
        Lightning.PubSub,
        state.source_topic,
        {:changed, name, state.source}
      )

      Logger.debug("Adaptors[#{state.source}]: persisted #{name}")
      :ok
    rescue
      e ->
        Logger.error(
          "Scheduler: upsert_adaptor(#{name}) failed: #{Exception.message(e)}"
        )

        :error
    end
  end

  defp merge_icon(record, shape, package_icons, source) do
    case Map.get(package_icons, shape) do
      %{data: bytes, ext: ext, sha256: sha} when is_binary(bytes) ->
        try do
          {:ok, ^sha} = IconCache.write!(source, record.name, shape, ext, bytes)

          record
          |> Map.put(:"icon_#{shape}_ext", ext)
          |> Map.put(:"icon_#{shape}_sha256", sha)
        rescue
          e ->
            Logger.warning(
              "Scheduler: IconCache.write!(#{record.name}, #{shape}) failed: #{Exception.message(e)}"
            )

            record
        end

      _ ->
        record
    end
  end

  # Top up icons on rows that currently have NULL on at least one shape.
  # Runs after the main upsert pass on every tick — cheap, scoped to
  # rows with gaps, and self-correcting after a strategy outage or a
  # past bug like the one that left every row iconless.
  defp heal_missing_icons(icons, _state) when map_size(icons) == 0, do: 0

  defp heal_missing_icons(icons, state) do
    state.source
    |> AdaptorsRepo.list_missing_icons()
    |> Enum.reduce(0, fn row, acc ->
      package_icons = Map.get(icons, row.name, %{})

      case apply_icons_to_existing(row, package_icons, state) do
        :updated -> acc + 1
        :unchanged -> acc
      end
    end)
  end

  defp reapply_icons(existing_rows, icons, state) do
    Enum.reduce(existing_rows, %{updated: 0, unchanged: 0}, fn row, acc ->
      package_icons = Map.get(icons, row.name, %{})

      case apply_icons_to_existing(row, package_icons, state) do
        :updated -> %{acc | updated: acc.updated + 1}
        :unchanged -> %{acc | unchanged: acc.unchanged + 1}
      end
    end)
  end

  # `row` is either an Adaptor struct (from list_adaptors/1) or a lean
  # map (from list_missing_icons/1) — both expose :name and the icon
  # sha256 fields, which is all we need.
  defp apply_icons_to_existing(_row, package_icons, _state)
       when map_size(package_icons) == 0,
       do: :unchanged

  defp apply_icons_to_existing(row, package_icons, state) do
    changes =
      [:square, :rectangle]
      |> Enum.reduce(%{}, fn shape, acc ->
        accumulate_icon_change(acc, shape, row, package_icons, state)
      end)

    if map_size(changes) > 0 do
      {1, _} = AdaptorsRepo.update_icons(row.name, state.source, changes)

      Phoenix.PubSub.broadcast(
        Lightning.PubSub,
        state.source_topic,
        {:changed, row.name, state.source}
      )

      :updated
    else
      :unchanged
    end
  end

  defp accumulate_icon_change(acc, shape, row, package_icons, state) do
    sha_key = :"icon_#{shape}_sha256"
    ext_key = :"icon_#{shape}_ext"

    with %{data: bytes, ext: ext, sha256: sha} <- Map.get(package_icons, shape),
         true <- is_binary(bytes),
         true <- Map.get(row, sha_key) != sha do
      try do
        {:ok, ^sha} = IconCache.write!(state.source, row.name, shape, ext, bytes)

        acc
        |> Map.put(ext_key, ext)
        |> Map.put(sha_key, sha)
      rescue
        e ->
          Logger.warning(
            "Scheduler: IconCache.write!(#{row.name}, #{shape}) failed: " <>
              Exception.message(e)
          )

          acc
      end
    else
      _ -> acc
    end
  end

  defp force_refresh_one(strategy, name, state) do
    case strategy.fetch_adaptor(name) do
      {:ok, record} ->
        record_with_source = Map.put(record, :source, state.source)

        try do
          {:ok, _} = AdaptorsRepo.upsert_adaptor(record_with_source)

          Phoenix.PubSub.broadcast(
            Lightning.PubSub,
            state.source_topic,
            {:changed, name, state.source}
          )

          Logger.info(
            "Adaptors[#{state.source}]: refresh_package(#{name}) ok version=#{record.version}"
          )

          :ok
        rescue
          e ->
            Logger.error(
              "Scheduler: upsert_adaptor(#{name}) failed: #{Exception.message(e)}"
            )

            {:error, {:upsert_failed, Exception.message(e)}}
        end

      {:error, reason} ->
        Logger.warning(
          "Scheduler: refresh_package(#{name}) strategy fetch failed: #{inspect(reason)}"
        )

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
