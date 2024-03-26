defmodule Lightning.UsageTracking.ReportWorker do
  @moduledoc """
  Worker to generate report for given day

  """
  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  alias Lightning.UsageTracking
  alias Lightning.UsageTracking.Client

  require Logger
  @impl Oban.Worker
  def perform(%{args: %{"date" => date_string}}) do
    date = Date.from_iso8601!(date_string)

    env = Application.get_env(:lightning, :usage_tracking)

    config = UsageTracking.find_enabled_daily_report_config()

    if env[:enabled] && config do
      cleartext_uuids_enabled = env[:cleartext_uuids_enabled]

      case UsageTracking.insert_report(config, cleartext_uuids_enabled, date) do
        {:ok, report} ->
          report.data
          |> Client.submit_metrics(env[:host])
          |> UsageTracking.update_report_submission!(report)

        _error ->
          nil
      end
    end

    :ok
  end
end
