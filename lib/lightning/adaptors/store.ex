defmodule Lightning.Adaptors.Store do
  @moduledoc """
  Stateless read facade over `Cachex`, `Lightning.Adaptors.Repo`, and the
  active `Lightning.Adaptors.Strategy`.

  Every public read helper wraps a `Cachex.fetch/4` whose fallback first
  consults the local Postgres projection (`Lightning.Adaptors.Repo`) and
  only invokes the Strategy as a last resort. Cachex's courier supplies
  blocking semantics and per-key coalescing of concurrent first-callers
  for free — there is no GenServer mailbox in front of the reads.

  ## Source tagging

  Each cache key carries the active `:source` (`:npm | :local`) read via
  `Lightning.Adaptors.Supervisor.source/1`, so the same package name can
  coexist across deployment modes without manual scrubbing (see §4.4 of
  `.context/adaptors/REWRITE-2026-05.md`).

  ## Commit vs ignore

  Successful Strategy/Repo lookups commit their projected value to the
  cache. Failures — empty `packages/1` results, unknown adaptors for
  `icon_meta/2`, Strategy errors — return `:ignore`, so a subsequent
  caller retries fresh rather than seeing a poisoned cache entry.

  ## Icons

  `icon/3` deliberately bypasses Cachex: the on-disk
  `Lightning.Adaptors.IconCache` is itself the cache, and the return
  value is a `Path.t/0` the controller serves via `send_file/3` (no
  binary on the BEAM heap).
  """

  alias Lightning.Adaptors.Config
  alias Lightning.Adaptors.IconCache
  alias Lightning.Adaptors.Repo, as: AdaptorsRepo
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  # Strategy and source are scoped to the supervisor instance — every
  # `Store` call resolves both from the per-instance `:persistent_term`
  # entry the supervisor populated at boot. No `Application.get_env`
  # reads in the hot path; no global mutable state in tests.

  @type sup :: atom()

  @type version_meta :: %{
          version: String.t(),
          integrity: String.t() | nil,
          size_bytes: integer() | nil,
          published_at: DateTime.t() | nil,
          deprecated: boolean()
        }

  @type icon_meta :: %{
          icon_square_ext: String.t() | nil,
          icon_rectangle_ext: String.t() | nil,
          icon_square_sha256: binary() | nil,
          icon_rectangle_sha256: binary() | nil
        }

  @type package_meta :: AdaptorsRepo.package_meta()

  @doc """
  Read the `schema_data` JSON blob for a single adaptor.

  Cache-then-Repo-then-Strategy. On Strategy success the full adaptor
  record is upserted into Postgres and the projected schema blob is
  committed to the cache.
  """
  @spec schema(sup(), String.t()) :: {:ok, map()} | {:error, term()}
  def schema(sup, name) do
    cache = AdaptorsSupervisor.cache_name(sup)
    source = AdaptorsSupervisor.source(sup)

    cache
    |> Cachex.fetch(
      {:schema, name, source},
      fn _key ->
        case AdaptorsRepo.get_adaptor(name, source) do
          %{schema_data: data} when not is_nil(data) ->
            {:commit, {:ok, data}}

          _ ->
            fetch_and_persist(sup, name, source, :schema_data)
        end
      end,
      timeout: Config.cache_timeout_ms()
    )
    |> unwrap()
  end

  @doc """
  Read the version history for a single adaptor as a list of lean
  per-version maps. See `t:version_meta/0` for the projected shape.
  """
  @spec versions(sup(), String.t()) ::
          {:ok, [version_meta()]} | {:error, term()}
  def versions(sup, name) do
    cache = AdaptorsSupervisor.cache_name(sup)
    source = AdaptorsSupervisor.source(sup)

    cache
    |> Cachex.fetch(
      {:versions, name, source},
      fn _key ->
        case AdaptorsRepo.list_versions(name, source) do
          [] -> fetch_and_persist(sup, name, source, :versions)
          rows -> {:commit, {:ok, project_versions(rows)}}
        end
      end,
      timeout: Config.cache_timeout_ms()
    )
    |> unwrap()
  end

  @doc """
  Resolve the on-disk path of one icon variant for an adaptor.

  Disk is the cache: a cache-hit on `IconCache.cached?/4` returns the
  path immediately; a cache-miss fetches bytes via the active Strategy
  and atomically writes them into the on-disk cache. Returns
  `{:error, :not_found}` when the icon variant is absent from the
  adaptor row (the row is the source of truth).
  """
  @spec icon(sup(), String.t(), :square | :rectangle) ::
          {:ok, Path.t()} | {:error, :not_found | term()}
  def icon(sup, name, shape) when shape in [:square, :rectangle] do
    source = AdaptorsSupervisor.source(sup)
    strategy = AdaptorsSupervisor.strategy(sup)

    with {:ok, meta} <- icon_meta(sup, name),
         {:ok, ext} <- ext_for_shape(meta, shape),
         {:ok, _sha256} <- sha256_for_shape(meta, shape) do
      if IconCache.cached?(source, name, shape, ext) do
        {:ok, IconCache.path(source, name, shape, ext)}
      else
        with {:ok, %{data: bytes, ext: ^ext}} <-
               strategy.fetch_icon(name, shape),
             {:ok, _sha256} <-
               IconCache.write!(source, name, shape, ext, bytes) do
          {:ok, IconCache.path(source, name, shape, ext)}
        end
      end
    end
  end

  @doc """
  Picker-facing lean projection: every adaptor row for the active
  source, minus heavy JSONB columns (`schema_data`, `dependencies`,
  `peer_dependencies`).

  An empty Repo result returns `{:ok, []}` but is **not** committed to
  the cache — during cold-start the Scheduler will fill the table on
  its next tick, and the next call will pick that up automatically.
  """
  @spec packages(sup()) :: {:ok, [package_meta()]} | {:error, term()}
  def packages(sup) do
    cache = AdaptorsSupervisor.cache_name(sup)
    source = AdaptorsSupervisor.source(sup)

    cache
    |> Cachex.fetch(
      {:packages, source},
      fn _key ->
        case AdaptorsRepo.list_package_metas(source) do
          [] -> {:ignore, {:ok, []}}
          metas -> {:commit, {:ok, metas}}
        end
      end,
      timeout: Config.cache_timeout_ms()
    )
    |> unwrap()
  end

  @doc """
  Cheap `{icon_<shape>_ext, icon_<shape>_sha256}` projection for the
  icon controller's sha-validation path. Pure metadata — no disk I/O.

  Unknown adaptors return `{:error, :not_found}` and are **not**
  cached, so a subsequent insert by the Scheduler becomes visible on
  the very next call.
  """
  @spec icon_meta(sup(), String.t()) ::
          {:ok, icon_meta()} | {:error, :not_found}
  def icon_meta(sup, name) do
    cache = AdaptorsSupervisor.cache_name(sup)
    source = AdaptorsSupervisor.source(sup)

    cache
    |> Cachex.fetch(
      {:icon_meta, name, source},
      fn _key ->
        case AdaptorsRepo.get_adaptor(name, source) do
          nil -> {:ignore, {:error, :not_found}}
          adaptor -> {:commit, {:ok, project_icon_meta(adaptor)}}
        end
      end,
      timeout: Config.cache_timeout_ms()
    )
    |> unwrap()
  end

  @doc """
  Re-warm Cachex from Postgres for the active source.

  Called by `Lightning.Adaptors.NodeMonitor` on `:nodeup` — a peer
  rejoining after a partition can't know which `{:changed, name, source}`
  broadcasts it missed, so it treats its entire local Cachex as
  suspect and overwrites from the DB.

  Uses `Cachex.put_many/2` (never `Cachex.clear/1`-then-fill) so
  concurrent callers never observe an empty cache and never trigger a
  spurious cold-miss Strategy fetch during the warm.
  """
  @spec warm_from_repo(sup()) :: :ok
  def warm_from_repo(sup) do
    cache = AdaptorsSupervisor.cache_name(sup)
    source = AdaptorsSupervisor.source(sup)

    metas = AdaptorsRepo.list_package_metas(source)

    icon_metas =
      Enum.map(metas, fn m ->
        {{:icon_meta, m.name, source}, {:ok, project_icon_meta(m)}}
      end)

    Cachex.put_many(
      cache,
      [{{:packages, source}, {:ok, metas}} | icon_metas]
    )

    :ok
  end

  @spec fetch_and_persist(atom(), String.t(), :npm | :local, atom()) ::
          {:commit, {:ok, term()}} | {:ignore, {:error, term()}}
  defp fetch_and_persist(sup, name, source, field) do
    case AdaptorsSupervisor.strategy(sup).fetch_adaptor(name) do
      {:ok, record} ->
        record = Map.put(record, :source, source)
        {:ok, _} = AdaptorsRepo.upsert_adaptor(record)
        {:commit, {:ok, Map.get(record, field)}}

      {:error, reason} ->
        {:ignore, {:error, reason}}
    end
  end

  @spec project_icon_meta(map()) :: icon_meta()
  defp project_icon_meta(adaptor) do
    Map.take(adaptor, [
      :icon_square_ext,
      :icon_rectangle_ext,
      :icon_square_sha256,
      :icon_rectangle_sha256
    ])
  end

  @spec project_versions([map()]) :: [version_meta()]
  defp project_versions(rows) do
    Enum.map(
      rows,
      &Map.take(&1, [
        :version,
        :integrity,
        :size_bytes,
        :published_at,
        :deprecated
      ])
    )
  end

  @spec ext_for_shape(icon_meta(), :square | :rectangle) ::
          {:ok, String.t()} | {:error, :not_found}
  defp ext_for_shape(meta, shape) do
    case Map.get(meta, :"icon_#{shape}_ext") do
      nil -> {:error, :not_found}
      ext -> {:ok, ext}
    end
  end

  @spec sha256_for_shape(icon_meta(), :square | :rectangle) ::
          {:ok, binary()} | {:error, :not_found}
  defp sha256_for_shape(meta, shape) do
    case Map.get(meta, :"icon_#{shape}_sha256") do
      nil -> {:error, :not_found}
      sha -> {:ok, sha}
    end
  end

  # `Cachex.fetch/4` returns one of:
  #   * `{:ok, value}` — cache hit (or coalesced peer of a `:commit`)
  #   * `{:commit, value}` — fallback ran and committed
  #   * `{:ignore, value}` — fallback ran and chose not to cache
  #   * `{:error, term}` — Cachex-side failure (fallback raised, etc.)
  #
  # Our fallbacks return `{:commit, {:ok, _}}` / `{:ignore, {:error, _}}`,
  # so the wrapper tuple's second element is itself the public
  # `{:ok, _} | {:error, _}` we want to return. Cachex-side `{:error, _}`
  # passes through unchanged.
  @spec unwrap(tuple()) :: {:ok, term()} | {:error, term()}
  defp unwrap({:ok, inner}), do: inner
  defp unwrap({:commit, inner}), do: inner
  defp unwrap({:ignore, inner}), do: inner
  defp unwrap({:error, _} = error), do: error
end
