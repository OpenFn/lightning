defmodule Lightning.UpdateCheck do
  @moduledoc """
  Finds out whether a newer full release is available in the configured
  image repository.

  The newest release is the version of the image the channel tag, `latest` by
  default, points at. It is read from the image's
  `org.opencontainers.image.version` label, or from its `IMAGE_TAG`
  environment variable for images built before the label was added. That
  takes three small requests, however many tags the repository has.

  When the image carries neither, or the channel tag doesn't exist, the
  highest full-release tag (`vX.Y.Z`, no pre-release suffix) is used
  instead, from one page of the repository's tag list. A version that isn't a
  full release fails the check with `:no_release_found`.

  Worker releases are found the same way, in the `openfn/ws-worker`
  repository by default. Which workers are connected, and so whether any are
  behind, is only known at the moment of asking, so the status holds the
  latest worker release and `worker_outdated?/2` compares against it.

  `check/2` does the network work. `Lightning.UpdateCheck.Checker` runs it on
  a timer and caches the result, which `status/1` reads without blocking.
  """

  alias Lightning.UpdateCheck.Checker
  alias Lightning.UpdateCheck.Registry
  alias Lightning.UpdateCheck.Releases

  require Logger

  @default_instructions_url "https://docs.openfn.org/documentation/deploy/options#technical-guidelines"

  @type status :: %{
          current: String.t(),
          latest: String.t(),
          latest_tag: String.t(),
          update_available?: boolean(),
          registry: String.t(),
          repository: String.t(),
          instructions_url: String.t(),
          checked_at: DateTime.t(),
          worker: worker_status() | nil
        }

  @type worker_status :: %{
          latest: String.t(),
          latest_tag: String.t(),
          registry: String.t(),
          repository: String.t()
        }

  @doc """
  Queries the registry and returns the update status.

  `config` takes the keys set under `config :lightning, :update_check`:
  `:registry`, `:repository`, `:tag`, `:instructions_url`, `:worker_registry`
  and `:worker_repository`. `current` is the running version, defaulting to
  the app's own.

  Workers are only checked when `:worker_repository` is set, and always
  against `:worker_registry`, never the app's `:registry`. A failed worker
  lookup is logged and leaves `:worker` as `nil` rather than failing the
  whole check.

  When no release can be found, because the channel tag's image names
  something other than a full release or there are no full-release tags, the
  check fails with `:no_release_found`. Reporting that as up to date would
  hide an instance that is behind.
  """
  @spec check(keyword(), String.t()) :: {:ok, status()} | {:error, term()}
  def check(config, current \\ current_version()) do
    with {:ok, latest} <- latest_release(config) do
      status =
        config
        |> build_status(current, latest)
        |> Map.put(:worker, check_worker(config))

      {:ok, status}
    end
  end

  @doc """
  Whether a worker reporting `version` is behind the latest worker release in
  `status`. Workers only started reporting their version recently, so one
  that reports none is behind. One whose version can't be parsed is not.
  """
  @spec worker_outdated?(status() | nil, String.t() | nil) :: boolean()
  def worker_outdated?(%{worker: %{latest: latest}}, nil)
      when is_binary(latest),
      do: true

  def worker_outdated?(%{worker: %{latest: latest}}, version)
      when is_binary(latest) do
    Releases.newer?(Version.parse!(latest), version)
  end

  def worker_outdated?(_status, _version), do: false

  @doc """
  Whether anything needs upgrading: the app itself, or any connected worker,
  given the versions the workers report.
  """
  @spec update_available?(status() | nil, [String.t() | nil]) :: boolean()
  def update_available?(nil, _worker_versions), do: false

  def update_available?(status, worker_versions) do
    status.update_available? or
      Enum.any?(worker_versions, &worker_outdated?(status, &1))
  end

  @doc """
  The most recent result from the checker, or `nil` when the check is
  disabled, hasn't completed yet, or the checker didn't answer in time.
  """
  @spec status(GenServer.server()) :: status() | nil
  def status(server \\ Checker) do
    Checker.status(server)
  end

  @doc """
  Runs a check now and waits for it. Returns `{:error, :disabled}` when the
  checker isn't running.
  """
  @spec check_now(GenServer.server()) :: {:ok, status()} | {:error, term()}
  def check_now(server \\ Checker) do
    Checker.check_now(server)
  end

  @doc """
  The version of the running app, such as `"2.19.1"`.
  """
  @spec current_version() :: String.t()
  def current_version do
    Lightning.release()[:vsn] |> to_string()
  end

  defp latest_release(config) do
    registry = Registry.new(config)
    channel_tag = Keyword.get(config, :tag, "latest")

    with {:ok, image_config, registry} <-
           Registry.image_config(registry, channel_tag) do
      case image_version(image_config) do
        nil -> newest_tag(registry)
        tag -> release(tag)
      end
    end
  end

  # The version label is the standard place for it. Images built before the
  # label was added carry the release tag in `IMAGE_TAG` instead.
  defp image_version(nil), do: nil

  defp image_version(image_config) do
    labels = image_config["Labels"] || %{}

    Enum.find(
      [
        labels["org.opencontainers.image.version"],
        env_var(image_config["Env"] || [], "IMAGE_TAG")
      ],
      &(&1 not in [nil, ""])
    )
  end

  defp env_var(env, name) do
    Enum.find_value(env, fn entry ->
      case String.split(entry, "=", parts: 2) do
        [^name, value] -> value
        _other -> nil
      end
    end)
  end

  # A channel tag whose image names anything but a full release, such as a
  # branch build, has no release to report.
  defp release(tag) do
    case Releases.parse(tag) do
      {:ok, version} -> {:ok, {tag, version}}
      :error -> {:error, :no_release_found}
    end
  end

  defp newest_tag(registry) do
    with {:ok, tags, _registry} <- Registry.list_tags(registry) do
      case Releases.stable_tags(tags) do
        [newest | _older] -> {:ok, newest}
        [] -> {:error, :no_release_found}
      end
    end
  end

  defp check_worker(config) do
    if config[:worker_repository] do
      worker_config = worker_config(config)

      case latest_release(worker_config) do
        {:ok, {latest_tag, latest_version}} ->
          %{
            latest: to_string(latest_version),
            latest_tag: latest_tag,
            registry: worker_config[:registry],
            repository: worker_config[:repository]
          }

        {:error, reason} ->
          Logger.warning("Worker update check failed: #{inspect(reason)}")
          nil
      end
    end
  end

  # Workers always follow the `latest` tag.
  defp worker_config(config) do
    [
      registry: config[:worker_registry],
      repository: config[:worker_repository],
      tag: "latest"
    ]
  end

  defp build_status(config, current, {latest_tag, latest_version}) do
    %{
      current: current,
      latest: to_string(latest_version),
      latest_tag: latest_tag,
      update_available?: Releases.newer?(latest_version, current),
      registry: config[:registry],
      repository: config[:repository],
      instructions_url: config[:instructions_url] || @default_instructions_url,
      checked_at: DateTime.utc_now()
    }
  end
end
