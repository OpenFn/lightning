defmodule Lightning.UsageTracking.ReportWorker do
  @moduledoc """
  Worker to generate report for given day

  """
  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  alias Lightning.UsageTracking

  require Logger
  @impl Oban.Worker
  def perform(%{args: %{"date" => date_string}}) do
    date = Date.from_iso8601!(date_string)

    config = UsageTracking.find_enabled_daily_report_config()

    if Lightning.Config.usage_tracking_enabled?() && config do
      cleartext_uuids_enabled =
        Lightning.Config.usage_tracking_cleartext_uuids_enabled?()

      case UsageTracking.insert_report(config, cleartext_uuids_enabled, date) do
        {:ok, report} ->
          UsageTracking.submit_report(
            report,
            Lightning.Config.usage_tracking_host()
          )

        _error ->
          nil
      end
    end

    :ok
  end
end
