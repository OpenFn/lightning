defmodule Lightning.UsageTracking.Worker do
  @moduledoc """
  Ensures repeated submissions of anonymised metrics to the Usage Tracker
  service


  """
  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  alias Lightning.Repo
  alias Lightning.UsageTracking.Client
  alias Lightning.UsageTracking.Configuration
  alias Lightning.UsageTracking.Report
  alias Lightning.UsageTracking.ReportData

  @impl Oban.Worker
  def perform(_opts) do
    env = Application.get_env(:lightning, :usage_tracking)

    if env[:enabled] do
      config = find_configuration()

      cleartext_uuids_enabled = env[:cleartext_uuids_enabled]

      host = env[:host]

      data = ReportData.generate(config, cleartext_uuids_enabled)

      Client.submit_metrics(data, host) |> create_report(data)
    end

    :ok
  end

  defp find_configuration do
    with nil <- Repo.one(Configuration) do
      Repo.insert!(%Configuration{})
    end
  end

  defp create_report(:ok, data) do
    %Report{data: data, submitted: true, submitted_at: DateTime.utc_now()}
    |> Repo.insert()
  end

  defp create_report(:error, data), do: %Report{data: data} |> Repo.insert()
end
