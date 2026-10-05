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

  A tick lists the source and fetches every adaptor whose `latest_version`
  changed. It also refetches an adaptor whose stored row has no schema, for
  the grace period set by `@schema_grace_ms` after the row's `updated_at`.
  jsDelivr mirrors a new version with some lag, so a schema missing inside
  that window may still arrive. After it, a missing schema is taken as
  really missing. A refetch that still finds no schema counts as touched.
  Icons are fetched in parallel and each changed adaptor is upserted with
  its icons. `refresh_package/2` refetches one adaptor without icons.
  """

  use GenServer

  alias Lightning.Adaptors.Catalogue
  alias Lightning.Adaptors.Config
  alias Lightning.Adaptors.IconCache
  alias Lightning.Adaptors.IconField
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  require Logger

  @fetch_max_concurrency 8
  @schema_grace_ms :timer.hours(1)
  @icons_task_timeout :timer.seconds(60)

  @doc """
  Starts the Scheduler. Required opts: `:name`, `:sup`, `:lock_key`,
  `:cache`, `:tasks`, `:source_topic`, `:refresh_interval` (tick interval
  in milliseconds; `0` disables the timer) and `:warn_when_empty` (whether
  booting on an empty catalogue with the timer disabled logs a warning).
  `:checked_at` is optional. It is a 1-arity function, defaulting to
  `&Catalogue.max_checked_at/1`, that reads the source's last-checked
  timestamp. It is called once at boot to work out the delay before the
  first tick.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    _ = Keyword.fetch!(opts, :sup)
    _ = Keyword.fetch!(opts, :lock_key)
    _ = Keyword.fetch!(opts, :cache)
    _ = Keyword.fetch!(opts, :tasks)
    _ = Keyword.fetch!(opts, :source_topic)
    _ = Keyword.fetch!(opts, :refresh_interval)
    _ = Keyword.fetch!(opts, :warn_when_empty)
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
  fetched and persisted, and how many adaptors the cycle failed to fetch
  or to write.
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
  and upsert failures are counted in `counts.errors`), `{:error, reason}`
  when it failed, or `{:error, {:refresh_failed, reason}}` when the cycle
  crashed.

  A caller whose `timeout` expires before the cycle finishes is dropped
  rather than replied to, so a late result never lands in its mailbox.
  """
  @spec await_refresh(GenServer.server(), timeout()) ::
          {:ok, refresh_counts()}
          | {:error, {:refresh_failed, term()} | term()}
  def await_refresh(scheduler_name, timeout) do
    GenServer.call(scheduler_name, {:await_refresh, timeout}, timeout)
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

  @doc """
  Whether a cycle has completed against a source that listed no adaptors
  at all, since this Scheduler started.

  That is the one outcome no row can record. An upstream answering with an
  empty list has told us there are no adaptors, and the empty catalogue it
  leaves behind is loaded rather than unloaded. Every other completed
  cycle leaves rows, which answer for themselves and keep answering after
  a restart. So this deliberately says nothing about them, and a source
  whose rows are later deleted reloads as it did before.

  A cycle that failed to list, fetch or write is not a completed one. We
  cannot tell a source with nothing in it from one we could not read.

  Answers `false` for a Scheduler that is unreachable.
  """
  @spec completed?(GenServer.server()) :: boolean()
  def completed?(scheduler_name) do
    GenServer.call(scheduler_name, :completed?)
  catch
    :exit, _reason -> false
  end

  @impl true
  def init(opts) do
    sup = Keyword.fetch!(opts, :sup)
    source_topic = Keyword.fetch!(opts, :source_topic)
    cache = Keyword.fetch!(opts, :cache)
    tasks = Keyword.fetch!(opts, :tasks)
    checked_at = Keyword.get(opts, :checked_at, &Catalogue.max_checked_at/1)

    source = AdaptorsSupervisor.source(sup)
    interval_ms = Keyword.fetch!(opts, :refresh_interval)

    state = %{
      sup: sup,
      source: source,
      interval_ms: interval_ms,
      warn_when_empty: Keyword.fetch!(opts, :warn_when_empty),
      source_topic: source_topic,
      cache: cache,
      tasks: tasks,
      checked_at: checked_at,
      refresh: nil,
      completed?: false,
      waiters: [],
      package_refreshes: %{},
      icon_refreshes: %{}
    }

    {:ok, state, {:continue, :check_catalogue}}
  end

  @impl true
  def handle_continue(:check_catalogue, state) do
    # The read runs even when interval_ms == 0. It is the only way a
    # deployment with the timer disabled learns its catalogue is empty.
    checked_at =
      case read_checked_at(state) do
        nil ->
          log_empty_catalogue(state)
          nil

        :error ->
          nil

        checked_at ->
          checked_at
      end

    delay = time_until_next_ms(checked_at, state.interval_ms)

    if state.interval_ms > 0 do
      Process.send_after(self(), :tick, delay)

      Logger.info(
        "Adaptors[#{state.source}]: scheduler started interval=#{state.interval_ms}ms " <>
          "next_tick_in=#{delay}ms"
      )
    else
      Logger.info(
        "Adaptors[#{state.source}]: scheduler started interval=0 (disabled)"
      )
    end

    {:noreply, state}
  end

  # An empty catalogue only needs an operator's attention when no timer will
  # fill it. With an interval set the first tick is already due.
  defp log_empty_catalogue(state) do
    cond do
      state.interval_ms > 0 ->
        Logger.info(
          "Adaptors[#{state.source}]: catalogue is empty at boot — refreshing now"
        )

      state.warn_when_empty ->
        Logger.warning(
          "Adaptors[#{state.source}]: catalogue is empty and refreshes are " <>
            "disabled (interval=0) — see ADAPTORS.md's \"Running without " <>
            "internet access\" section"
        )

      true ->
        :ok
    end
  end

  defp read_checked_at(state) do
    state.checked_at.(state.source)
  rescue
    e in DBConnection.ConnectionError ->
      Logger.warning(
        "Adaptors[#{state.source}]: scheduler could not read max_checked_at: " <>
          Exception.message(e)
      )

      :error
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

    reply_waiters(state.waiters, result)

    completed? =
      state.completed? or match?({:ok, %{listed: 0, errors: 0}}, result)

    {:noreply, %{state | refresh: nil, completed?: completed?, waiters: []}}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{refresh: %Task{ref: ref}} = state
      ) do
    Logger.warning(
      "Adaptors[#{state.source}]: refresh task crashed: #{inspect(reason)} — " <>
        "replying error to #{length(state.waiters)} waiter(s)"
    )

    reply_waiters(state.waiters, {:error, {:refresh_failed, reason}})

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

  defp deadline(:infinity), do: :infinity

  defp deadline(timeout) when is_integer(timeout),
    do: System.monotonic_time(:millisecond) + timeout

  # A caller that outlived its own timeout is no longer expecting a reply.
  defp reply_waiters(waiters, result) do
    now = System.monotonic_time(:millisecond)

    Enum.each(waiters, fn {from, deadline} ->
      if deadline == :infinity or deadline > now do
        GenServer.reply(from, result)
      end
    end)
  end

  @impl true
  def handle_call(:completed?, _from, state) do
    {:reply, state.completed?, state}
  end

  def handle_call(:refresh_now, _from, state) do
    Logger.info("Adaptors[#{state.source}]: refresh_now requested")
    {:reply, :ok, maybe_start_refresh(state)}
  end

  def handle_call({:await_refresh, timeout}, from, state) do
    Logger.debug(
      "Adaptors[#{state.source}]: await_refresh attached (#{length(state.waiters) + 1} waiters)"
    )

    state = %{state | waiters: [{from, deadline(timeout)} | state.waiters]}
    {:noreply, maybe_start_refresh(state)}
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

  defp maybe_start_refresh(state) do
    if state.refresh, do: state, else: start_refresh(state)
  end

  defp start_refresh(state) do
    task = Task.Supervisor.async_nolink(state.tasks, fn -> do_refresh(state) end)
    %{state | refresh: task}
  end

  defp do_refresh(state) do
    started_at = System.monotonic_time(:millisecond)
    strategy = AdaptorsSupervisor.strategy(state.sup)

    # One query feeds both the icons task and the version diff below.
    existing_rows = Catalogue.list_adaptors(state.source)
    prior_etags = prior_etags_from_rows(existing_rows)

    existing_by_name = Map.new(existing_rows, fn a -> {a.name, a} end)

    icons_task =
      Task.Supervisor.async_nolink(state.tasks, fn ->
        strategy.fetch_icons(prior_etags: prior_etags)
      end)

    case strategy.list_adaptors() do
      {:ok, upstream} ->
        {fetched, changed, fetch_errors} =
          state.tasks
          |> Task.Supervisor.async_stream_nolink(
            upstream,
            &fetch_if_changed(strategy, &1, existing_by_name, state),
            max_concurrency: @fetch_max_concurrency,
            ordered: false,
            on_timeout: :kill_task,
            timeout:
              Config.strategy_opts(strategy)[:http_timeout] ||
                :timer.seconds(30)
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

        # Rows fetched this tick got their icons in persist_with_icons/3.
        # The rest, touched or errored, get theirs here, so an icon-only
        # upstream change lands even when the version doesn't bump.
        fetched_names = MapSet.new(fetched, & &1.name)

        unfetched_rows =
          Enum.reject(existing_rows, &MapSet.member?(fetched_names, &1.name))

        healed = reapply_icons(unfetched_rows, icons, state).updated
        not_modified = count_not_modified(icons)

        listed = length(upstream)
        touched = listed - changed - fetch_errors
        errors = fetch_errors + (changed - persisted)
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
    existing = Map.get(existing_by_name, name)
    same_version? = !is_nil(existing) && existing.latest_version == version

    if same_version? and
         (not is_nil(existing.schema_data) or older_than_grace?(existing)) do
      Catalogue.touch_checked_at(name, state.source)
      :touched
    else
      case strategy.fetch_adaptor(name) do
        # Refetched only because the stored schema was nil, and upstream
        # still has none. Nothing to persist, so don't broadcast a change.
        {:ok, %{schema_data: nil}} when same_version? ->
          Catalogue.touch_checked_at(name, state.source)
          :touched

        {:ok, %{latest_version: fetched_version} = record} ->
          Logger.debug(
            "Adaptors[#{state.source}]: fetched #{name}@#{fetched_version}"
          )

          {:fetched, keep_stored_schema(record, existing)}

        {:error, reason} ->
          Logger.warning(
            "Scheduler: fetch_adaptor(#{name}) failed: #{inspect(reason)}"
          )

          {:error, reason}
      end
    end
  end

  defp older_than_grace?(%{updated_at: updated_at}) do
    DateTime.diff(DateTime.utc_now(), updated_at, :millisecond) >
      @schema_grace_ms
  end

  # jsDelivr 404s for a version it has not mirrored yet, which is
  # indistinguishable from a schema the source really dropped. On the
  # periodic path we keep what we have. An operator refresh takes upstream
  # as-is and is where a real removal lands.
  defp keep_stored_schema(
         %{schema_data: nil} = record,
         %{schema_data: stored} = row
       )
       when not is_nil(stored) do
    %{record | schema_data: stored, schema_sha256: row.schema_sha256}
  end

  defp keep_stored_schema(record, _existing), do: record

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
          IconCache.write!(source, record.name, shape, ext, bytes, sha)

          record
          |> Map.put(IconField.ext(shape), ext)
          |> Map.put(IconField.sha256(shape), sha)
          |> maybe_put_etag(shape, Map.get(entry, :etag))
        rescue
          e ->
            Logger.warning(
              "Scheduler: IconCache.write!(#{record.name}, #{shape}) failed: #{Exception.message(e)}"
            )

            record
        end

      :not_modified ->
        # Upstream answered 304, so the row's icon and etag stay as they are.
        record

      _ ->
        record
    end
  end

  # A nil etag (the Local strategy sends none) leaves whatever the row
  # already has in place rather than clearing it.
  defp maybe_put_etag(record, _shape, nil), do: record

  defp maybe_put_etag(record, shape, etag) when is_binary(etag) do
    Map.put(record, IconField.etag(shape), etag)
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
    sha_key = IconField.sha256(shape)
    etag_key = IconField.etag(shape)

    case Map.get(package_icons, shape) do
      %{data: bytes, ext: ext, sha256: sha} = entry when is_binary(bytes) ->
        if Map.get(row, sha_key) == sha do
          # Same bytes already on disk, but the etag may still have moved.
          maybe_accumulate_etag(acc, etag_key, row, Map.get(entry, :etag))
        else
          accumulate_fetched_icon(acc, shape, row, entry, ext, sha, bytes, state)
        end

      :not_modified ->
        # 304, so nothing to write.
        acc

      _ ->
        acc
    end
  end

  defp accumulate_fetched_icon(acc, shape, row, entry, ext, sha, bytes, state) do
    sha_key = IconField.sha256(shape)
    ext_key = IconField.ext(shape)
    etag_key = IconField.etag(shape)

    IconCache.write!(state.source, row.name, shape, ext, bytes, sha)

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

  # A nil etag never overwrites what's on the row. A value equal to the
  # row's current etag is skipped too, to avoid a no-op write.
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

  # A row or shape with no etag is left out rather than kept as an empty
  # entry. The strategy treats an absent entry as no prior etag and sends
  # no If-None-Match.
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
