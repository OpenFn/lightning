defmodule Lightning.UsageTracking.ReportWorker do
  @moduledoc """
  Worker to generate report for given day

  """
  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  alias Lightning.Repo
  alias Lightning.UsageTracking
  alias Lightning.UsageTracking.Client
  alias Lightning.UsageTracking.Report
  alias Lightning.UsageTracking.ReportData

  require Logger
  @impl Oban.Worker
  def perform(%{args: %{"date" => date_string}}) do
    date = Date.from_iso8601!(date_string)

    env = Application.get_env(:lightning, :usage_tracking)

    config = UsageTracking.find_enabled_daily_report_config()

    if env[:enabled] && config do
      cleartext_uuids_enabled = env[:cleartext_uuids_enabled]

      host = env[:host]

      data = ReportData.generate(config, cleartext_uuids_enabled, date)

      Client.submit_metrics(data, host) |> create_report(data, date)
    end

    :ok
  end

  defp create_report(:ok, data, date) do
    %Report{
      data: data,
      report_date: date,
      submitted: true,
      submitted_at: DateTime.utc_now()
    }
    |> Repo.insert()
  end

  defp create_report(:error, data, date) do
    %Report{data: data, report_date: date} |> Repo.insert()
  end
end
