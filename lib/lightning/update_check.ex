defmodule Lightning.UpdateCheck do
  @moduledoc """
  Finds out whether a newer full release is available in the configured
  image repository.

  The newest release is the highest full-release tag (`vX.Y.Z`, no
  pre-release suffix) whose manifest digest equals that of the channel tag,
  `latest` by default. This is the same tagging used by the public
  `openfn/lightning` repository on Docker Hub and by private repositories that
  hold embargoed security releases. When the channel tag doesn't exist, the
  highest full-release tag is used instead.

  `check/2` does the network work. `Lightning.UpdateCheck.Checker` runs it on
  a timer and caches the result, which `status/1` reads without blocking.
  """

  alias Lightning.UpdateCheck.Checker
  alias Lightning.UpdateCheck.Registry
  alias Lightning.UpdateCheck.Releases

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
          checked_at: DateTime.t()
        }

  @doc """
  Queries the registry and returns the update status.

  `config` takes the keys set under `config :lightning, :update_check`:
  `:registry`, `:repository`, `:tag`, `:username`, `:password` and
  `:instructions_url`. `current` is the running version, defaulting to the
  app's own.
  """
  @spec check(keyword(), String.t()) :: {:ok, status()} | {:error, term()}
  def check(
        config \\ Lightning.Config.update_check(),
        current \\ current_version()
      ) do
    registry = Registry.new(config)
    channel_tag = Keyword.get(config, :tag, "latest")

    with {:ok, tags, registry} <- Registry.list_tags(registry),
         {:ok, latest} <-
           find_latest(registry, Releases.stable_tags(tags), channel_tag, tags) do
      {:ok, build_status(config, current, latest)}
    end
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
    "2.19.1"
    # Lightning.release()[:vsn] |> to_string()
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
