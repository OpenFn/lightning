defmodule Lightning.AdaptorRefreshWorker do
  @moduledoc """
  Oban worker that periodically refreshes the adaptor registry, icons,
  and credential schemas from their upstream sources.

  Scheduled via cron when `ADAPTOR_REFRESH_INTERVAL_HOURS` is configured.
  Returns `:ok` even on partial failure since retries are not useful for
  transient network issues — the next scheduled run will try again.
  """

  use Oban.Worker,
    queue: :background,
    max_attempts: 1,
    unique: [period: 3600]

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
      {:registry, safe_call(fn -> Lightning.AdaptorRegistry.refresh() end)},
      {:icons, safe_call(fn -> Lightning.AdaptorIcons.refresh() end)},
      {:schemas, safe_call(fn -> Lightning.CredentialSchemas.refresh() end)}
    ]

    errors =
      results
      |> Enum.filter(fn {_, result} -> match?({:error, _}, result) end)
      |> Enum.map(fn {name, {:error, reason}} -> {name, reason} end)

    if errors == [] do
      Logger.info("Scheduled adaptor refresh completed successfully")
      Lightning.API.broadcast("adaptor:refresh", {:refresh_all, node()})
    else
      Logger.warning(
        "Scheduled adaptor refresh partially failed: #{inspect(errors)}"
      )

      # Only broadcast to other nodes if at least one refresh succeeded
      if length(errors) < length(results) do
        Lightning.API.broadcast("adaptor:refresh", {:refresh_all, node()})
      end
    end

    :ok
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
