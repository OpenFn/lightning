defmodule Lightning.Adaptors.Store do
  @moduledoc """
  Cached reads over `Lightning.Adaptors.Catalogue`.

  Every read checks the instance's Cachex first and falls back to the
  catalogue table. Reads never write to the catalogue: the
  `Lightning.Adaptors.Scheduler` is the only writer, so a row with no
  schema means the source has none and `schema/2` answers `"{}"`, while
  an unknown name returns `{:error, :not_found}`. `icon/3` returns a path on disk,
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

  @type icon_meta :: %{
          icon_square_ext: String.t() | nil,
          icon_rectangle_ext: String.t() | nil,
          icon_square_sha256: binary() | nil,
          icon_rectangle_sha256: binary() | nil
        }

  @type package_meta :: Catalogue.package_meta()

  @typedoc """
  One `t:Lightning.Adaptors.Catalogue.catalogue_entry/0` with its icon
  fields rendered to URLs, as the catalogue endpoint serves it.
  """
  @type rendered_entry :: %{
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
          {{DateTime.t() | nil, non_neg_integer()}, [rendered_entry()]}

  @doc """
  Returns the adaptor's credential schema as a JSON binary, not decoded.
  An adaptor with no schema yields `"{}"`; an unknown name
  `{:error, :not_found}`.
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
          nil ->
            {:ignore, {:error, :not_found}}

          %{schema_data: data} when not is_nil(data) ->
            {:commit, {:ok, data}}

          _ ->
            {:commit, {:ok, "{}"}}
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
         {:ok, expected_sha} <- sha256_for_shape(meta, shape) do
      if IconCache.cached?(source, name, shape, ext, expected_sha) do
        {:ok, IconCache.path(source, name, shape, ext, expected_sha)}
      else
        cache
        |> Cachex.fetch(
          {:icon_bytes, source, name, shape},
          fn _key ->
            fetch_icon_bytes(strategy, source, name, shape, ext, expected_sha)
          end,
          timeout: Config.cache_timeout_ms()
        )
        |> unwrap()
      end
    end
  end

  defp fetch_icon_bytes(strategy, source, name, shape, ext, expected_sha) do
    case strategy.fetch_icon(name, shape) do
      {:ok, %{data: bytes, ext: ^ext}} ->
        case :crypto.hash(:sha256, bytes) do
          ^expected_sha ->
            {:ignore,
             {:ok,
              IconCache.write!(source, name, shape, ext, bytes, expected_sha)}}

          got ->
            {:commit,
             {:error, {:icon_sha_mismatch, expected: expected_sha, got: got}}}
        end

      {:ok, %{ext: other_ext}} ->
        {:commit, {:error, {:ext_mismatch, expected: ext, got: other_ext}}}

      # A transport failure says nothing about the icon, so it is never
      # cached; only a disagreement between the row and the bytes is.
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

    {stamp,
     source |> Catalogue.catalogue() |> Enum.map(&render_entry(&1, source))}
  end

  @spec render_entry(Catalogue.catalogue_entry(), Catalogue.source()) ::
          rendered_entry()
  defp render_entry(entry, source) do
    %{
      name: entry.name,
      latest_version:
        if(source == :local, do: "local", else: entry.latest_version),
      versions: if(source == :local, do: ["local"], else: entry.versions),
      repository: entry.repository,
      icon_urls: %{
        square: AdaptorIconURL.build(entry.name, entry, :square),
        rectangle: AdaptorIconURL.build(entry.name, entry, :rectangle)
      }
    }
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
  # Every fallback returns an inner `{:ok, _} | {:error, _}`, whichever
  # wrapper it chooses, so the wrapper tuple's second element is itself
  # the public value we want to return, including a committed
  # `{:error, _}`, which comes back as `{:ok, {:error, _}}` on a later
  # hit. Cachex-side `{:error, _}` passes through unchanged.
  @spec unwrap(tuple()) :: {:ok, term()} | {:error, term()}
  defp unwrap({:ok, inner}), do: inner
  defp unwrap({:commit, inner}), do: inner
  defp unwrap({:ignore, inner}), do: inner
  defp unwrap({:error, _} = error), do: error
end
