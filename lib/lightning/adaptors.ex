defmodule Lightning.Adaptors do
  @moduledoc """
  Public interface to the adaptor catalogue.

  ## Catalogue reads

    * `packages/0,1` - every adaptor for the active source
    * `versions/2` - published versions of one adaptor
    * `get_adaptor/1` - one adaptor as a `Lightning.Adaptors.Package`,
      or `nil`
    * `catalogue/0` and `catalogue_stamp/0` - the full catalogue and its
      ETag basis
    * `schema/1,2` and `icon/2,3` - per-adaptor assets

  ## Adaptor specs

  An adaptor spec is the `"name@version"` string a job stores, where the
  version may be a semver, `latest`, `local`, or absent.

    * `parse_spec/1` - split a spec into `{name, version}`
    * `valid_format?/1` - does a string match the strict spec format
    * `resolve_version/2` - turn `latest`/`local` into a concrete version
    * `to_wire/1` - render a spec for the worker's install step

  ## Refreshing

    * `refresh_now/0,1`, `refresh_package/1,2`, `refresh_icons/0,1`
    * `seed_from_file/2` - populate the catalogue from a JSON snapshot,
      used by `mix lightning.seed_adaptors_from_file` and
      `Lightning.Release`

  Most functions come in a dual-arity shape: the zero-/single-arg form
  passes the compile-time default supervisor name `@sup`; the extra-arity
  form accepts an explicit supervisor name for test isolation.
  `get_adaptor/1`, `resolve_version/2`, `catalogue/0`, and
  `catalogue_stamp/0` are exceptions — none of them go through `Store`'s
  cache process. `get_adaptor/1` and `resolve_version/2` read the active
  source from `Config.current_source/0` (a process-independent
  `Application.get_env` read), so there's nothing to swap. `catalogue/0`
  and `catalogue_stamp/0` read it from `AdaptorsSupervisor.source/1`
  instead — a boot-time snapshot owned by a running supervisor — so
  those two are only correct for `@sup`, the default supervisor.
  """

  alias Lightning.Adaptors.Config
  alias Lightning.Adaptors.PackageName
  alias Lightning.Adaptors.Repo
  alias Lightning.Adaptors.Scheduler
  alias Lightning.Adaptors.Store
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  defmodule Package do
    @moduledoc """
    One catalogue adaptor, as seen by callers outside
    `Lightning.Adaptors`. Not wire-serialised and not an `Ecto.Schema`.
    """

    @type t :: %__MODULE__{
            name: String.t(),
            source: :npm | :local,
            latest_version: String.t() | nil
          }

    defstruct [:name, :source, :latest_version]
  end

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

  @doc """
  One adaptor from the active source's catalogue, by bare package name.

  Takes a name, not a `name@version` spec — use `parse_spec/1` first if
  you have a spec. Returns `nil` when the catalogue has no such adaptor,
  including when it is empty.
  """
  @spec get_adaptor(String.t()) :: Package.t() | nil
  def get_adaptor(name) when is_binary(name) do
    case Repo.get_adaptor(name, Config.current_source()) do
      nil ->
        nil

      adaptor ->
        %Package{
          name: adaptor.name,
          source: adaptor.source,
          latest_version: adaptor.latest_version
        }
    end
  end

  @doc """
  Split an adaptor spec into `{name, version}`, with `version` `nil` when
  the spec carries none. Returns `{nil, nil}` for a string that isn't a
  well-formed spec.
  """
  @spec parse_spec(String.t()) :: {String.t() | nil, String.t() | nil}
  def parse_spec(spec) when is_binary(spec) do
    case Regex.run(PackageName.strict_format(), spec) do
      [_, name, version] -> {name, version}
      [_, name] -> {name, nil}
      _ -> {nil, nil}
    end
  end

  @doc """
  Whether a string is a well-formed adaptor spec: a package name plus an
  optional `@version`, with no newlines or shell metacharacters.
  """
  @spec valid_format?(String.t()) :: boolean()
  def valid_format?(spec) when is_binary(spec),
    do: Regex.match?(PackageName.strict_format(), spec)

  @doc """
  Render an adaptor spec for the worker's install step, resolving
  `latest` to a concrete version and preserving `local`.
  """
  @spec to_wire(String.t() | nil) :: String.t()
  defdelegate to_wire(spec), to: PackageName

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
