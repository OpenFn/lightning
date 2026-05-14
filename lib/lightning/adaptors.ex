defmodule Lightning.Adaptors do
  @moduledoc """
  Public facade for all adaptor metadata.

  Delegates reads to `Lightning.Adaptors.Store`, refresh calls to
  `Lightning.Adaptors.Scheduler`, and version resolution to
  `Lightning.Adaptors.Repo`. No logic lives here.

  All functions come in a dual-arity shape: the zero-/single-arg form
  passes the compile-time default supervisor name `@sup`; the extra-arity
  form accepts an explicit supervisor name for test isolation.
  `resolve_version/2` is the single exception — it has no sup arity because
  it reads the global Repo directly.
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

  @spec schema(String.t()) :: {:ok, map()} | {:error, term()}
  def schema(pkg), do: schema(@sup, pkg)

  @spec schema(atom(), String.t()) :: {:ok, map()} | {:error, term()}
  def schema(sup, pkg), do: Store.schema(sup, pkg)

  @spec icon(String.t(), :square | :rectangle) ::
          {:ok, Path.t()} | {:error, term()}
  def icon(pkg, shape), do: icon(@sup, pkg, shape)

  @spec icon(atom(), String.t(), :square | :rectangle) ::
          {:ok, Path.t()} | {:error, term()}
  def icon(sup, pkg, shape), do: Store.icon(sup, pkg, shape)

  @spec resolve_version(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :not_found}
  def resolve_version(name, requested) when requested in ["latest", "local"] do
    case Repo.get_adaptor(name, Config.current_source()) do
      %{latest_version: v} -> {:ok, v}
      nil -> {:error, :not_found}
    end
  end

  def resolve_version(_name, version), do: {:ok, version}

  @spec refresh_now() :: :ok | {:error, :not_leader}
  def refresh_now, do: refresh_now(@sup)

  @spec refresh_now(atom()) :: :ok | {:error, :not_leader}
  def refresh_now(sup),
    do: Scheduler.refresh_now(AdaptorsSupervisor.scheduler_name(sup))

  @spec refresh_package(String.t()) :: :ok | {:error, :not_leader | term()}
  def refresh_package(name) when is_binary(name), do: refresh_package(@sup, name)

  @spec refresh_package(atom(), String.t()) ::
          :ok | {:error, :not_leader | term()}
  def refresh_package(sup, name) when is_binary(name),
    do: Scheduler.refresh_package(AdaptorsSupervisor.scheduler_name(sup), name)

  @doc false
  def icon_meta(name), do: icon_meta(@sup, name)

  @doc false
  def icon_meta(sup, name), do: Store.icon_meta(sup, name)
end
