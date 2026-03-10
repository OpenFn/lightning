defmodule Lightning.AdaptorRefreshWorker do
  @moduledoc """
  Oban worker that periodically refreshes the adaptor registry and
  credential schemas from their upstream sources, storing results in
  the database via `Lightning.AdaptorData`.

  Scheduled via cron when `ADAPTOR_REFRESH_INTERVAL_HOURS` is configured.
  Returns `:ok` even on partial failure since retries are not useful for
  transient network issues — the next scheduled run will try again.
  """

  use Oban.Worker,
    queue: :background,
    max_attempts: 1,
    unique: [period: 60]

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Lightning.AdaptorRegistry.local_adaptors_enabled?() do
      Logger.info("Skipping scheduled adaptor refresh: local adaptors mode")
      :ok
    else
      do_refresh()
    end
  end

  defp do_refresh do
    Logger.info("Starting scheduled adaptor refresh")

    results = [
      {:registry, safe_call(&refresh_registry/0)},
      {:schemas, safe_call(&refresh_schemas/0)}
    ]

    errors =
      results
      |> Enum.filter(fn {_, result} -> match?({:error, _}, result) end)
      |> Enum.map(fn {name, {:error, reason}} -> {name, reason} end)

    refreshed_kinds =
      results
      |> Enum.filter(fn {_, result} -> match?({:ok, _}, result) end)
      |> Enum.map(fn {kind, _} -> to_string(kind) end)

    if refreshed_kinds != [] do
      Lightning.AdaptorData.Cache.broadcast_invalidation(refreshed_kinds)
    end

    if errors == [] do
      Logger.info("Scheduled adaptor refresh completed successfully")
    else
      Logger.warning(
        "Scheduled adaptor refresh partially failed: #{inspect(errors)}"
      )
    end

    :ok
  end

  defp refresh_registry do
    adaptors = Lightning.AdaptorRegistry.fetch()

    if adaptors == [] do
      {:error, :empty_results}
    else
      data = Jason.encode!(adaptors)
      Lightning.AdaptorData.put("registry", "all", data)
      {:ok, length(adaptors)}
    end
  end

  defp refresh_schemas do
    Lightning.CredentialSchemas.fetch_and_store()
  end

  defp safe_call(fun) do
    case fun.() do
      :ok -> {:ok, :done}
      {:ok, _} = ok -> ok
      {:error, _} = error -> error
    end
  rescue
    error ->
      Logger.error("Adaptor refresh error: #{Exception.message(error)}")
      {:error, Exception.message(error)}
  end
end
