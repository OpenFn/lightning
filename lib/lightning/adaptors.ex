defmodule Lightning.Adaptors do
  @moduledoc """
  Public facade for all adaptor metadata.

  Delegates reads to `Lightning.Adaptors.Store`, refresh calls to
  `Lightning.Adaptors.Scheduler`, and version resolution to
  `Lightning.Adaptors.Repo`. `seed_from_file/2` owns the snapshot-loading
  logic used by both `mix lightning.seed_adaptors_from_file` and
  `Lightning.Release`.

  Most functions come in a dual-arity shape: the zero-/single-arg form
  passes the compile-time default supervisor name `@sup`; the extra-arity
  form accepts an explicit supervisor name for test isolation.
  `resolve_version/2`, `catalogue/0`, and `catalogue_stamp/0` are
  exceptions — they read the global Repo directly, not a running
  supervisor process, so there is nothing to swap for test isolation.
  """

  alias Lightning.Adaptors.Config
  alias Lightning.Adaptors.Repo
  alias Lightning.Adaptors.Scheduler
  alias Lightning.Adaptors.Store
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  @sup Lightning.Adaptors

  @type package_meta :: Store.package_meta()
  @type version_meta :: Store.version_meta()

  @spec packages() :: {:ok, [package_meta()]} | {:error, :timeout | term()}
  def packages, do: packages(@sup)

  @spec packages(atom()) :: {:ok, [package_meta()]} | {:error, :timeout | term()}
  def packages(sup), do: Store.packages(sup)

  @spec versions(atom(), String.t()) ::
          {:ok, [version_meta()]} | {:error, term()}
  def versions(sup, pkg), do: Store.versions(sup, pkg)

  @spec schema(String.t()) :: {:ok, String.t()} | {:error, term()}
  def schema(pkg), do: schema(@sup, pkg)

  @spec schema(atom(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def schema(sup, pkg), do: Store.schema(sup, pkg)

  @spec icon(String.t(), :square | :rectangle) ::
          {:ok, Path.t()} | {:error, term()}
  def icon(pkg, shape), do: icon(@sup, pkg, shape)

  @spec icon(atom(), String.t(), :square | :rectangle) ::
          {:ok, Path.t()} | {:error, term()}
  def icon(sup, pkg, shape), do: Store.icon(sup, pkg, shape)

  @doc """
  Full catalogue for the active source: every adaptor's `name`,
  `latest_version`, `repository`, icon fields, and full version list.
  Reads `Repo` directly, like `resolve_version/2`.
  """
  @spec catalogue() :: [Repo.catalogue_entry()]
  def catalogue, do: Repo.catalogue(AdaptorsSupervisor.source(@sup))

  @doc """
  ETag basis for `catalogue/0` — see `Repo.catalogue_stamp/1`.
  """
  @spec catalogue_stamp() :: {DateTime.t() | nil, non_neg_integer()}
  def catalogue_stamp, do: Repo.catalogue_stamp(AdaptorsSupervisor.source(@sup))

  @spec resolve_version(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :not_found}
  def resolve_version(name, requested) when requested in ["latest", "local"] do
    case Repo.get_adaptor(name, Config.current_source()) do
      %{latest_version: v} -> {:ok, v}
      nil -> {:error, :not_found}
    end
  end

  def resolve_version(_name, version), do: {:ok, version}

  @spec refresh_now() :: :ok | {:error, term()}
  def refresh_now, do: refresh_now(@sup)

  @spec refresh_now(atom()) :: :ok | {:error, term()}
  def refresh_now(sup),
    do: Scheduler.refresh_now(AdaptorsSupervisor.global_scheduler_name(sup))

  @spec refresh_package(String.t()) :: :ok | {:error, :not_found | term()}
  def refresh_package(name) when is_binary(name), do: refresh_package(@sup, name)

  @spec refresh_package(atom(), String.t()) ::
          :ok | {:error, :not_found | term()}
  def refresh_package(sup, name) when is_binary(name),
    do:
      Scheduler.refresh_package(
        AdaptorsSupervisor.global_scheduler_name(sup),
        name
      )

  @spec refresh_icons() ::
          {:ok, %{updated: non_neg_integer(), unchanged: non_neg_integer()}}
          | {:error, term()}
  def refresh_icons, do: refresh_icons(@sup)

  @spec refresh_icons(atom()) ::
          {:ok, %{updated: non_neg_integer(), unchanged: non_neg_integer()}}
          | {:error, term()}
  def refresh_icons(sup),
    do: Scheduler.refresh_icons(AdaptorsSupervisor.global_scheduler_name(sup))

  @doc false
  def icon_meta(name), do: icon_meta(@sup, name)

  @doc false
  def icon_meta(sup, name), do: Store.icon_meta(sup, name)

  @doc """
  Populate the adaptor catalogue from a JSON snapshot file, without
  reaching npm.

  The file is a JSON array of adaptor records in the shape
  `Lightning.Adaptors.Repo.upsert_adaptor/1` accepts — the same shape
  `mix lightning.download_adaptor_registry_cache` writes.

  `opts`:

    * `:source` - `:npm` (default) or `:local`.
    * `:replace` - when `true`, deletes every existing row for that
      source before seeding, so the file becomes the source's entire
      contents rather than a merge. The delete and every upsert run in
      one transaction, so a bad record aborts the whole seed rather
      than leaving the source partially replaced.
  """
  @spec seed_from_file(Path.t(), keyword()) :: {:ok, non_neg_integer()}
  def seed_from_file(path, opts \\ []) do
    source = Keyword.get(opts, :source, :npm)
    replace? = Keyword.get(opts, :replace, false)

    records =
      path
      |> File.read!()
      |> Jason.decode!()
      |> Enum.map(&normalize_snapshot_record(&1, source))

    {:ok, _} =
      Lightning.Repo.transaction(fn ->
        if replace?, do: Repo.delete_all_for_source(source)
        Enum.each(records, &Repo.upsert_adaptor/1)
      end)

    {:ok, length(records)}
  end

  # Top-level record keys and per-version keys map onto known schema
  # fields, so they can be turned into existing atoms. `dependencies` and
  # `peer_dependencies` values are left with string keys — that's the
  # shape the `:map` columns already store.
  defp normalize_snapshot_record(record, source) when is_map(record) do
    record
    |> atomize_known_keys()
    |> Map.put(:source, source)
    |> Map.update(:versions, [], fn versions ->
      Enum.map(versions, &atomize_known_keys/1)
    end)
  end

  defp atomize_known_keys(map) do
    Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end
end
