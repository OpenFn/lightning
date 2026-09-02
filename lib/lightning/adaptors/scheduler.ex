defmodule Lightning.Adaptors.Scheduler do
  @moduledoc """
  Cluster-singleton GenServer that refreshes the catalogue from the
  strategy, on a timer and on demand, persisting through
  `Lightning.Adaptors.Catalogue` and broadcasting `{:changed, name, source}`
  on the source topic.

  The first tick is due one `refresh_interval` after the catalogue's most
  recent check, so a restart does not refetch straight away; an empty
  catalogue ticks at once. An interval of `0` disables the timer and
  leaves only on-demand refreshes.

  A tick lists the source, fetches only the adaptors whose
  `latest_version` changed, fetches icons in parallel, and upserts each
  changed adaptor with its icons. `refresh_package/2` refetches one
  adaptor without icons.
  """

  use GenServer

  alias Lightning.Adaptors.Catalogue
  alias Lightning.Adaptors.Config
  alias Lightning.Adaptors.IconCache
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  require Logger

  @fetch_max_concurrency 8
  @icons_task_timeout :timer.seconds(60)

  @doc """
  Starts the Scheduler. Required opts: `:name`, `:sup`, `:lock_key`,
  `:cache`, `:tasks`, `:source_topic`.
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
  Starts a refresh tick, or lets one already in flight continue.
  """
  @spec refresh_now(GenServer.server()) :: :ok | {:error, term()}
  def refresh_now(scheduler_name) do
    GenServer.call(scheduler_name, :refresh_now)
  end

  @doc """
  Refetches and persists one adaptor whether or not its version changed.
  Waits up to 30 seconds.
  """
  @spec refresh_package(GenServer.server(), String.t()) ::
          :ok | {:error, :not_found | term()}
  def refresh_package(scheduler_name, name) do
    GenServer.call(scheduler_name, {:refresh_package, name}, 30_000)
  end

  @typedoc """
  One refresh cycle's tallies: adaptors the upstream listing returned,
  how many of those had a changed `latest_version`, how many were
  fetched and persisted, and how many per-adaptor fetches failed.
  """
  @type refresh_counts :: %{
          listed: non_neg_integer(),
          changed: non_neg_integer(),
          fetched: non_neg_integer(),
          errors: non_neg_integer()
        }

  @doc """
  Starts a refresh cycle, or joins the one in flight, and waits for it to
  complete.

  Returns `{:ok, counts}` when the listing succeeded (per-adaptor fetch
  failures are counted in `counts.errors`), `{:error, reason}` when it
  failed, or `{:error, {:refresh_failed, reason}}` when the cycle crashed.
  """
  @spec await_refresh(GenServer.server(), timeout()) ::
          {:ok, refresh_counts()}
          | {:error, {:refresh_failed, term()} | term()}
  def await_refresh(scheduler_name, timeout) do
    GenServer.call(scheduler_name, :await_refresh, timeout)
  end

  @doc """
  Refetches every adaptor's icons and updates the rows whose icon bytes
  changed, leaving other fields untouched.

  Returns `{:ok, %{updated: n, unchanged: m}}`, `{:error, reason}` if the
  fetch fails, or `{:error, {:refresh_failed, reason}}` if the task
  crashed.
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
        time_until_next_ms(Catalogue.max_checked_at(source), interval_ms)

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
       tasks: tasks,
       refresh: nil,
       waiters: [],
       package_refreshes: %{},
       icon_refreshes: %{}
     }}
  end

  @impl true
  def handle_info(:tick, state) do
    if state.interval_ms > 0 do
      Process.send_after(self(), :tick, state.interval_ms)
    end

    if state.refresh do
      Logger.debug(
        "Adaptors[#{state.source}]: tick coalesced into in-flight refresh"
      )

      {:noreply, state}
    else
      {:noreply, start_refresh(state)}
    end
  end

  @impl true
  def handle_info({ref, result}, %{refresh: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    Logger.info(
      "Adaptors[#{state.source}]: refresh complete, replying to " <>
        "#{length(state.waiters)} waiter(s)"
    )

    Enum.each(state.waiters, &GenServer.reply(&1, result))

    {:noreply, %{state | refresh: nil, waiters: []}}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{refresh: %Task{ref: ref}} = state
      ) do
    Logger.warning(
      "Adaptors[#{state.source}]: refresh task crashed: #{inspect(reason)} — " <>
        "replying error to #{length(state.waiters)} waiter(s)"
    )

    Enum.each(
      state.waiters,
      &GenServer.reply(&1, {:error, {:refresh_failed, reason}})
    )

    {:noreply, %{state | refresh: nil, waiters: []}}
  end

  def handle_info({ref, result}, state)
      when is_map_key(state.package_refreshes, ref) do
    Process.demonitor(ref, [:flush])
    {from, package_refreshes} = Map.pop!(state.package_refreshes, ref)
    GenServer.reply(from, result)
    {:noreply, %{state | package_refreshes: package_refreshes}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state)
      when is_map_key(state.package_refreshes, ref) do
    Logger.warning(
      "Adaptors[#{state.source}]: refresh_package task crashed: #{inspect(reason)}"
    )

    {from, package_refreshes} = Map.pop!(state.package_refreshes, ref)
    GenServer.reply(from, {:error, {:refresh_failed, reason}})
    {:noreply, %{state | package_refreshes: package_refreshes}}
  end

  def handle_info({ref, result}, state)
      when is_map_key(state.icon_refreshes, ref) do
    Process.demonitor(ref, [:flush])
    {from, icon_refreshes} = Map.pop!(state.icon_refreshes, ref)
    GenServer.reply(from, result)
    {:noreply, %{state | icon_refreshes: icon_refreshes}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state)
      when is_map_key(state.icon_refreshes, ref) do
    Logger.warning(
      "Adaptors[#{state.source}]: refresh_icons task crashed: #{inspect(reason)}"
    )

    {from, icon_refreshes} = Map.pop!(state.icon_refreshes, ref)
    GenServer.reply(from, {:error, {:refresh_failed, reason}})
    {:noreply, %{state | icon_refreshes: icon_refreshes}}
  end

  # A late task result must not crash the singleton.
  def handle_info(msg, state) do
    Logger.warning(
      "Adaptors[#{state.source}]: scheduler ignoring unexpected message: #{inspect(msg)}"
    )

    {:noreply, state}
  end

  @impl true
  def handle_call(:refresh_now, _from, state) do
    Logger.info("Adaptors[#{state.source}]: refresh_now requested")
    send(self(), :tick)
    {:reply, :ok, state}
  end

  def handle_call(:await_refresh, from, state) do
    Logger.debug(
      "Adaptors[#{state.source}]: await_refresh attached (#{length(state.waiters) + 1} waiters)"
    )

    state = %{state | waiters: [from | state.waiters]}
    state = if state.refresh, do: state, else: start_refresh(state)
    {:noreply, state}
  end

  def handle_call({:refresh_package, name}, from, state) do
    Logger.info("Adaptors[#{state.source}]: refresh_package(#{name}) requested")

    strategy = AdaptorsSupervisor.strategy(state.sup)

    task =
      Task.Supervisor.async_nolink(state.tasks, fn ->
        force_refresh_one(strategy, name, state)
      end)

    {:noreply, put_in(state.package_refreshes[task.ref], from)}
  end

  def handle_call(:refresh_icons, from, state) do
    Logger.info("Adaptors[#{state.source}]: refresh_icons requested")
    strategy = AdaptorsSupervisor.strategy(state.sup)

    task =
      Task.Supervisor.async_nolink(state.tasks, fn ->
        do_refresh_icons(strategy, state)
      end)

    {:noreply, put_in(state.icon_refreshes[task.ref], from)}
  end

  defp do_refresh_icons(strategy, state) do
    existing = Catalogue.list_adaptors(state.source)
    prior_etags = prior_etags_from_rows(existing)

    case strategy.fetch_icons(prior_etags: prior_etags) do
      {:ok, icons} ->
        result = reapply_icons(existing, icons, state)

        Logger.info(
          "Adaptors[#{state.source}]: refresh_icons done " <>
            "rows=#{length(existing)} icons=#{map_size(icons)} " <>
            "updated=#{result.updated} unchanged=#{result.unchanged}"
        )

        {:ok, result}

      {:error, reason} ->
        Logger.warning(
          "Adaptors[#{state.source}]: refresh_icons strategy fetch failed: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp start_refresh(state) do
    task = Task.Supervisor.async_nolink(state.tasks, fn -> do_refresh(state) end)
    %{state | refresh: task}
  end

  defp do_refresh(state) do
    started_at = System.monotonic_time(:millisecond)
    strategy = AdaptorsSupervisor.strategy(state.sup)

    # Single DB round-trip serves both the icons-task input (prior etags)
    # and the version diff used below to decide which adaptors to fetch.
    existing_rows = Catalogue.list_adaptors(state.source)
    prior_etags = prior_etags_from_rows(existing_rows)

    existing_by_name =
      Map.new(existing_rows, fn a -> {a.name, a.latest_version} end)

    icons_task =
      Task.Supervisor.async_nolink(state.tasks, fn ->
        strategy.fetch_icons(prior_etags: prior_etags)
      end)

    case strategy.list_adaptors() do
      {:ok, upstream} ->
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
        not_modified = count_not_modified(icons)

        listed = length(upstream)
        touched = listed - changed - errors
        duration_ms = System.monotonic_time(:millisecond) - started_at

        Logger.info(
          "Adaptors[#{state.source}]: refresh tick listed=#{listed} " <>
            "changed=#{changed} touched=#{touched} fetched=#{persisted} " <>
            "icons=#{map_size(icons)} healed=#{healed} " <>
            "not_modified=#{not_modified} " <>
            "errors=#{errors} duration=#{duration_ms}ms"
        )

        {:ok,
         %{listed: listed, changed: changed, fetched: persisted, errors: errors}}

      {:error, reason} ->
        Logger.warning("Scheduler: list_adaptors failed: #{inspect(reason)}")
        _ = await_icons(icons_task)
        duration_ms = System.monotonic_time(:millisecond) - started_at

        Logger.info(
          "Adaptors[#{state.source}]: refresh tick listed=0 changed=0 " <>
            "touched=0 fetched=0 icons=0 errors=1 duration=#{duration_ms}ms"
        )

        {:error, reason}
    end
  end

  defp fetch_if_changed(
         strategy,
         %{name: name, latest_version: version},
         existing_by_name,
         state
       ) do
    if Map.get(existing_by_name, name) == version do
      Catalogue.touch_checked_at(name, state.source)
      :touched
    else
      case strategy.fetch_adaptor(name) do
        # latest_version is bound in the head rather than read inside the
        # Logger call. A log message is only built when its level is enabled,
        # so a field read inside one isn't exercised.
        {:ok, %{latest_version: version} = record} ->
          Logger.debug("Adaptors[#{state.source}]: fetched #{name}@#{version}")

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

    case upsert_and_broadcast(record_with_icons, name, state) do
      :ok ->
        Logger.debug("Adaptors[#{state.source}]: persisted #{name}")
        :ok

      {:error, _reason} ->
        :error
    end
  end

  defp merge_icon(record, shape, package_icons, source) do
    case Map.get(package_icons, shape) do
      %{data: bytes, ext: ext, sha256: sha} = entry when is_binary(bytes) ->
        try do
          {:ok, ^sha} = IconCache.write!(source, record.name, shape, ext, bytes)

          record
          |> Map.put(:"icon_#{shape}_ext", ext)
          |> Map.put(:"icon_#{shape}_sha256", sha)
          |> maybe_put_etag(shape, Map.get(entry, :etag))
        rescue
          e ->
            Logger.warning(
              "Scheduler: IconCache.write!(#{record.name}, #{shape}) failed: #{Exception.message(e)}"
            )

            record
        end

      :not_modified ->
        # Upstream confirmed unchanged — leave row's existing icon and
        # etag in place. Counted in the tick summary via
        # count_not_modified/1.
        record

      _ ->
        record
    end
  end

  # Stamp the etag onto the record only when the strategy supplied one
  # (NPM 200 entries always have the key; Local omits it). A nil etag is
  # not stamped — we preserve whatever was already on the row.
  defp maybe_put_etag(record, _shape, nil), do: record

  defp maybe_put_etag(record, shape, etag) when is_binary(etag) do
    Map.put(record, :"icon_#{shape}_etag", etag)
  end

  # Tops up icons on rows currently missing at least one shape. Runs
  # after the main upsert pass on every tick — cheap, scoped to rows
  # with gaps, and self-correcting after a strategy outage.
  defp heal_missing_icons(icons, _state) when map_size(icons) == 0, do: 0

  defp heal_missing_icons(icons, state) do
    state.source
    |> Catalogue.list_missing_icons()
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
      {1, _} = Catalogue.update_icons(row.name, state.source, changes)

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
    etag_key = :"icon_#{shape}_etag"

    case Map.get(package_icons, shape) do
      %{data: bytes, ext: ext, sha256: sha} = entry when is_binary(bytes) ->
        if Map.get(row, sha_key) == sha do
          # Same bytes already on disk; the etag may still need
          # refreshing if the strategy gave us a new (non-nil) value
          # that differs from what we have. nil never clobbers.
          maybe_accumulate_etag(acc, etag_key, row, Map.get(entry, :etag))
        else
          accumulate_fetched_icon(acc, shape, row, entry, ext, sha, bytes, state)
        end

      :not_modified ->
        # 304 confirmed — nothing to write, etag already current.
        acc

      _ ->
        acc
    end
  end

  defp accumulate_fetched_icon(acc, shape, row, entry, ext, sha, bytes, state) do
    sha_key = :"icon_#{shape}_sha256"
    ext_key = :"icon_#{shape}_ext"
    etag_key = :"icon_#{shape}_etag"

    {:ok, ^sha} = IconCache.write!(state.source, row.name, shape, ext, bytes)

    acc
    |> Map.put(ext_key, ext)
    |> Map.put(sha_key, sha)
    |> maybe_accumulate_etag(etag_key, row, Map.get(entry, :etag))
  rescue
    e ->
      Logger.warning(
        "Scheduler: IconCache.write!(#{row.name}, #{shape}) failed: " <>
          Exception.message(e)
      )

      acc
  end

  # nil → preserve existing etag on the row (do not clobber).
  # value matching the row's current etag → no-op (avoid no-op write).
  # value differing → emit the change.
  defp maybe_accumulate_etag(acc, _etag_key, _row, nil), do: acc

  defp maybe_accumulate_etag(acc, etag_key, row, etag) when is_binary(etag) do
    if Map.get(row, etag_key) == etag do
      acc
    else
      Map.put(acc, etag_key, etag)
    end
  end

  defp force_refresh_one(strategy, name, state) do
    case strategy.fetch_adaptor(name) do
      {:ok, %{latest_version: version} = record} ->
        record_with_source = Map.put(record, :source, state.source)

        case upsert_and_broadcast(record_with_source, name, state) do
          :ok ->
            Logger.info(
              "Adaptors[#{state.source}]: refresh_package(#{name}) ok version=#{version}"
            )

            :ok

          {:error, _reason} = error ->
            error
        end

      {:error, reason} ->
        Logger.warning(
          "Scheduler: refresh_package(#{name}) strategy fetch failed: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  # The rescue deliberately covers only the upsert and the broadcast. Callers
  # log their own success line outside it, so a mistake in that line crashes
  # rather than being reported back as a failed upsert.
  defp upsert_and_broadcast(record, name, state) do
    {:ok, _} = Catalogue.upsert_adaptor(record)

    Phoenix.PubSub.broadcast(
      Lightning.PubSub,
      state.source_topic,
      {:changed, name, state.source}
    )

    :ok
  rescue
    e ->
      Logger.error(
        "Scheduler: upsert_adaptor(#{name}) failed: #{Exception.message(e)}"
      )

      {:error, {:upsert_failed, Exception.message(e)}}
  end

  # Project a list of adaptor rows to the prior-etag map shape expected
  # by `Strategy.fetch_icons/1`: `%{name => %{shape => etag}}`. Rows
  # whose etags are both nil are skipped entirely (no empty inner map);
  # within a row, only shapes with a non-nil etag are kept. The consumer
  # treats absence as "no prior etag, send no If-None-Match", so an empty
  # entry would be wasteful but harmless — we drop it for clarity.
  @spec prior_etags_from_rows([map()]) :: %{
          String.t() => %{optional(:square | :rectangle) => String.t()}
        }
  defp prior_etags_from_rows(rows) do
    Enum.reduce(rows, %{}, fn row, acc ->
      inner =
        %{}
        |> maybe_put_shape_etag(:square, Map.get(row, :icon_square_etag))
        |> maybe_put_shape_etag(:rectangle, Map.get(row, :icon_rectangle_etag))

      if map_size(inner) == 0 do
        acc
      else
        Map.put(acc, row.name, inner)
      end
    end)
  end

  defp maybe_put_shape_etag(map, _shape, nil), do: map

  defp maybe_put_shape_etag(map, shape, etag) when is_binary(etag),
    do: Map.put(map, shape, etag)

  # Used in the tick summary log.
  defp count_not_modified(icons) do
    Enum.reduce(icons, 0, fn {_name, shapes}, acc ->
      Enum.reduce(shapes, acc, fn
        {_shape, :not_modified}, n -> n + 1
        {_shape, _}, n -> n
      end)
    end)
  end

  defp time_until_next_ms(nil, _interval_ms), do: 0

  defp time_until_next_ms(%DateTime{} = last, interval_ms) do
    next = DateTime.add(last, interval_ms, :millisecond)
    diff = DateTime.diff(next, DateTime.utc_now(), :millisecond)
    max(0, diff)
  end
end
