defmodule Lightning.AdaptorRefreshWorker do
  @moduledoc """
  Oban worker that periodically refreshes the adaptor registry, the
  icon manifest, and credential schemas from their upstream sources,
  storing results in the database via `Lightning.AdaptorData`.

  Scheduled via cron when `ADAPTOR_REFRESH_INTERVAL_HOURS` is configured:

    * `1..23` — runs every N hours
    * `>= 24` — runs once daily at 04:00 UTC (cron has no "every N days";
      values of 24, 36, 48, ... all collapse to the same daily slot)
    * `0` or unset — disabled

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

    registry_result = safe_call(&refresh_registry/0)

    # Rebuild the icon manifest from the (just-refreshed) registry. No
    # upstream traffic — the manifest is computed from the in-DB registry.
    # PNG prefetch stays manual because it does hit GitHub.
    manifest_result =
      case registry_result do
        {:ok, _} -> safe_call(&refresh_icon_manifest/0)
        _ -> {:error, :skipped_registry_failed}
      end

    results = [
      {:registry, registry_result},
      {:icon_manifest, manifest_result},
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

  defp refresh_icon_manifest do
    case Lightning.AdaptorIcons.refresh_manifest() do
      {:ok, manifest} -> {:ok, map_size(manifest)}
      error -> error
    end
  end

  defp refresh_schemas do
    Lightning.CredentialSchemas.fetch_and_store()
  end

  defp safe_call(fun) do
    fun.()
  rescue
    error ->
      Logger.error("Adaptor refresh error: #{Exception.message(error)}")
      {:error, Exception.message(error)}
  end
end
