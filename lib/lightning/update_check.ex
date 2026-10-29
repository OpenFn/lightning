defmodule Lightning.UpdateCheck do
  @moduledoc """
  Finds out whether a newer full release is available in the configured
  image repository.

  The newest release is the highest full-release tag (`vX.Y.Z`, no
  pre-release suffix) whose manifest digest equals that of the channel tag,
  `latest` by default. This is the tagging used by the public
  `openfn/lightning` repository on Docker Hub. When the channel tag doesn't
  exist, the highest full-release tag is used instead.

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

  # How many of the newest release tags to compare against the channel tag's
  # digest before giving up. Each comparison is one HEAD request.
  @max_candidates 10

  @default_instructions_url "https://docs.openfn.org/documentation/deploy/options#technical-guidelines"

  @type status :: %{
          current: String.t(),
          latest: String.t() | nil,
          latest_tag: String.t() | nil,
          update_available?: boolean(),
          registry: String.t(),
          repository: String.t(),
          instructions_url: String.t(),
          checked_at: DateTime.t(),
          worker: worker_status() | nil
        }

  @type worker_status :: %{
          latest: String.t() | nil,
          latest_tag: String.t() | nil,
          registry: String.t(),
          repository: String.t()
        }

  @doc """
  Queries the registry and returns the update status.

  `config` takes the keys set under `config :lightning, :update_check`:
  `:registry`, `:repository`, `:tag`, `:instructions_url`, `:worker_registry` and `:worker_repository`. `current`
  is the running version, defaulting to the app's own.

  Workers are only checked when `:worker_repository` is set. A failed worker
  lookup is logged and leaves `:worker` as `nil` rather than failing the
  whole check.
  """
  @spec check(keyword(), String.t()) :: {:ok, status()} | {:error, term()}
  def check(
        config \\ Lightning.Config.update_check(),
        current \\ current_version()
      ) do
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
  `status`. A worker that reports no version, or one that can't be parsed, is
  never behind.
  """
  @spec worker_outdated?(status() | nil, String.t() | nil) :: boolean()
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

    with {:ok, tags, registry} <- Registry.list_tags(registry) do
      find_latest(registry, Releases.stable_tags(tags), channel_tag, tags)
    end
  end

  defp check_worker(config) do
    if config[:worker_repository] do
      worker_config = worker_config(config)

      case latest_release(worker_config) do
        {:ok, latest} ->
          {latest_tag, latest_version} = latest || {nil, nil}

          %{
            latest: latest_version && to_string(latest_version),
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
      registry: config[:worker_registry] || config[:registry],
      repository: config[:worker_repository],
      tag: "latest"
    ]
  end

  defp find_latest(_registry, [], _channel_tag, _tags), do: {:ok, nil}

  defp find_latest(registry, [newest | _] = stable, channel_tag, tags) do
    if channel_tag in tags do
      with {:ok, channel_digest, registry} <-
             Registry.digest(registry, channel_tag) do
        match_digest(
          registry,
          Enum.take(stable, @max_candidates),
          channel_digest
        )
      end
    else
      {:ok, newest}
    end
  end

  defp match_digest(_registry, _candidates, nil), do: {:ok, nil}

  defp match_digest(registry, candidates, channel_digest) do
    Enum.reduce_while(candidates, {:ok, nil}, fn {tag, _version} = candidate,
                                                 {:ok, nil} ->
      case Registry.digest(registry, tag) do
        {:ok, ^channel_digest, _registry} -> {:halt, {:ok, candidate}}
        {:ok, _other, _registry} -> {:cont, {:ok, nil}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp build_status(config, current, latest) do
    {latest_tag, latest_version} = latest || {nil, nil}
    latest_string = latest_version && to_string(latest_version)

    %{
      current: current,
      latest: latest_string,
      latest_tag: latest_tag,
      update_available?: Releases.newer?(latest_version, current),
      registry: config[:registry],
      repository: config[:repository],
      instructions_url: config[:instructions_url] || @default_instructions_url,
      checked_at: DateTime.utc_now()
    }
  end
end
