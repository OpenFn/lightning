defmodule Lightning.Adaptors.Store do
  @moduledoc """
  Cached reads over `Lightning.Adaptors.Catalogue`.

  Every read checks the instance's Cachex first and falls back to the
  catalogue table. `schema/2` and `versions/2` also fetch from the
  strategy when the row has no data yet and persist what they get; this
  only fills gaps on adaptors already in the catalogue, and an unknown
  name returns `{:error, :not_found}`. `icon/3` returns a path on disk,
  fetching the bytes from the strategy on the first miss. `catalogue/1`
  caches the picker payload already rendered, together with the ETag
  stamp that describes it.
  """

  alias Lightning.Adaptors.Catalogue
  alias Lightning.Adaptors.Config
  alias Lightning.Adaptors.IconCache
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor
  alias LightningWeb.AdaptorIconURL

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

  @type package_meta :: Catalogue.package_meta()

  @type catalogue_entry :: %{
          name: String.t(),
          latest_version: String.t(),
          versions: [String.t()],
          repository: String.t() | nil,
          icon_urls: %{
            square: String.t() | nil,
            rectangle: String.t() | nil
          }
        }

  @type catalogue ::
          {{DateTime.t() | nil, non_neg_integer()}, [catalogue_entry()]}

  @doc """
  Returns the adaptor's credential schema as a JSON binary, not decoded.
  """
  @spec schema(sup(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def schema(sup, name) do
    cache = AdaptorsSupervisor.cache_name(sup)
    source = AdaptorsSupervisor.source(sup)

    cache
    |> Cachex.fetch(
      {:schema, name, source},
      fn _key ->
        case Catalogue.get_adaptor(name, source) do
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
  Returns the adaptor's version history as `t:version_meta/0` maps.
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
        case Catalogue.list_versions(name, source) do
          [] -> fetch_and_persist(sup, name, source, :versions)
          rows -> {:commit, {:ok, project_versions(rows)}}
        end
      end,
      timeout: Config.cache_timeout_ms()
    )
    |> unwrap()
  end

  @doc """
  Returns the on-disk path of one icon shape for the adaptor, or
  `{:error, :not_found}` when the adaptor row has no such icon.
  """
  @spec icon(sup(), String.t(), :square | :rectangle) ::
          {:ok, Path.t()} | {:error, :not_found | term()}
  def icon(sup, name, shape) when shape in [:square, :rectangle] do
    cache = AdaptorsSupervisor.cache_name(sup)
    source = AdaptorsSupervisor.source(sup)
    strategy = AdaptorsSupervisor.strategy(sup)

    with {:ok, meta} <- icon_meta(sup, name),
         {:ok, ext} <- ext_for_shape(meta, shape),
         {:ok, _sha256} <- sha256_for_shape(meta, shape) do
      if IconCache.cached?(source, name, shape, ext) do
        {:ok, IconCache.path(source, name, shape, ext)}
      else
        cache
        |> Cachex.fetch(
          {:icon_bytes, source, name, shape},
          fn _key -> fetch_icon_bytes(strategy, source, name, shape, ext) end,
          timeout: Config.cache_timeout_ms()
        )
        |> unwrap()
      end
    end
  end

  defp fetch_icon_bytes(strategy, source, name, shape, ext) do
    case strategy.fetch_icon(name, shape) do
      {:ok, %{data: bytes, ext: ^ext}} ->
        {:ok, _sha} = IconCache.write!(source, name, shape, ext, bytes)
        {:ignore, {:ok, IconCache.path(source, name, shape, ext)}}

      {:ok, %{ext: other_ext}} ->
        {:ignore, {:error, {:ext_mismatch, expected: ext, got: other_ext}}}

      {:error, _} = err ->
        {:ignore, err}
    end
  end

  @doc """
  Returns every adaptor for the active source, without the `schema_data`,
  `dependencies` and `peer_dependencies` columns.
  """
  @spec packages(sup()) :: {:ok, [package_meta()]} | {:error, term()}
  def packages(sup) do
    cache = AdaptorsSupervisor.cache_name(sup)
    source = AdaptorsSupervisor.source(sup)

    cache
    |> Cachex.fetch(
      {:packages, source},
      fn _key ->
        case Catalogue.list_package_metas(source) do
          [] -> {:ignore, {:ok, []}}
          metas -> {:commit, {:ok, metas}}
        end
      end,
      timeout: Config.cache_timeout_ms()
    )
    |> unwrap()
  end

  @doc """
  Returns the picker catalogue for the active source as
  `{stamp, rendered_entries}`.

  The ETag stamp and the payload it describes are cached as one entry so
  a 304 can be answered without re-reading the projection, and so the two
  can never drift apart.
  """
  @spec catalogue(sup()) :: {:ok, catalogue()} | {:error, term()}
  def catalogue(sup) do
    cache = AdaptorsSupervisor.cache_name(sup)
    source = AdaptorsSupervisor.source(sup)

    cache
    |> Cachex.fetch(
      {:catalogue, source},
      fn _key ->
        case build_catalogue(source) do
          {_stamp, []} = empty -> {:ignore, {:ok, empty}}
          filled -> {:commit, {:ok, filled}}
        end
      end,
      timeout: Config.cache_timeout_ms()
    )
    |> unwrap()
  end

  @doc """
  Returns the extension and sha256 of each icon shape for the adaptor,
  without touching disk, or `{:error, :not_found}` for an unknown name.
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
        case Catalogue.get_adaptor(name, source) do
          nil -> {:ignore, {:error, :not_found}}
          adaptor -> {:commit, {:ok, project_icon_meta(adaptor)}}
        end
      end,
      timeout: Config.cache_timeout_ms()
    )
    |> unwrap()
  end

  @doc """
  Overwrites the cached package list, icon metadata and catalogue from the
  database. An empty catalogue is left uncached, as `catalogue/1` does.
  """
  @spec warm_from_repo(sup()) :: :ok
  def warm_from_repo(sup) do
    cache = AdaptorsSupervisor.cache_name(sup)
    source = AdaptorsSupervisor.source(sup)

    metas = Catalogue.list_package_metas(source)

    icon_metas =
      Enum.map(metas, fn m ->
        {{:icon_meta, m.name, source}, {:ok, project_icon_meta(m)}}
      end)

    catalogue =
      case build_catalogue(source) do
        {_stamp, []} -> []
        filled -> [{{:catalogue, source}, {:ok, filled}}]
      end

    Cachex.put_many(
      cache,
      [{{:packages, source}, {:ok, metas}} | icon_metas] ++ catalogue
    )

    :ok
  end

  # The stamp is read before the projection so it can only ever be older
  # than the payload it describes, never newer: a lagging stamp costs a
  # client one extra 200, a leading one would serve a stale 304.
  @spec build_catalogue(Catalogue.source()) :: catalogue()
  defp build_catalogue(source) do
    stamp = Catalogue.catalogue_stamp(source)

    {stamp, source |> Catalogue.catalogue() |> Enum.map(&render_entry/1)}
  end

  @spec render_entry(Catalogue.catalogue_entry()) :: catalogue_entry()
  defp render_entry(entry) do
    %{
      name: entry.name,
      latest_version: entry.latest_version,
      versions: entry.versions,
      repository: entry.repository,
      icon_urls: %{
        square: AdaptorIconURL.build(entry.name, entry, :square),
        rectangle: AdaptorIconURL.build(entry.name, entry, :rectangle)
      }
    }
  end

  # Lazy fetches only fill gaps on adaptors already in the catalogue;
  # they never add one.
  @spec fetch_and_persist(atom(), String.t(), :npm | :local, atom()) ::
          {:commit, {:ok, term()}} | {:ignore, {:error, term()}}
  defp fetch_and_persist(sup, name, source, field) do
    if Catalogue.get_adaptor(name, source) do
      fetch_and_persist_known(sup, name, source, field)
    else
      {:ignore, {:error, :not_found}}
    end
  end

  defp fetch_and_persist_known(sup, name, source, field) do
    case AdaptorsSupervisor.strategy(sup).fetch_adaptor(name) do
      {:ok, %{name: ^name} = record} ->
        record =
          record
          |> Map.put(:source, source)
          |> normalize_schema_data()

        {:ok, _} = Catalogue.upsert_adaptor(record)
        {:commit, {:ok, record |> Map.get(field) |> project_field(field)}}

      {:ok, %{name: other}} ->
        {:ignore, {:error, {:name_mismatch, other}}}

      {:error, reason} ->
        {:ignore, {:error, reason}}
    end
  end

  # Both cache paths must store the same projected shape.
  defp project_field(rows, :versions) when is_list(rows),
    do: project_versions(rows)

  defp project_field(value, _field), do: value

  # Strategies should emit `schema_data` as a JSON binary, but legacy
  # call paths (and tests) may still hand us a map. Normalize here so
  # the cached value matches what subsequent DB-backed reads return.
  defp normalize_schema_data(%{schema_data: data} = record)
       when is_map(data) and not is_struct(data) do
    %{record | schema_data: Jason.encode!(data)}
  end

  defp normalize_schema_data(record), do: record

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
