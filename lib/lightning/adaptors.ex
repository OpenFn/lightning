defmodule Lightning.Adaptors do
  @moduledoc """
  Public facade for all adaptor metadata.

  Delegates reads to `Lightning.Adaptors.Store`, refresh calls to
  `Lightning.Adaptors.Scheduler`, and version resolution to
  `Lightning.Adaptors.Repo`. No logic lives here.

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

  @spec versions(String.t()) :: {:ok, [version_meta()]} | {:error, term()}
  def versions(pkg), do: versions(@sup, pkg)

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
end
