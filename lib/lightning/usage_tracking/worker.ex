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

  @impl Oban.Worker
  def perform(_opts) do
    if Application.get_env(:lightning, :usage_tracking)[:enabled] do
      find_configuration()

      host = Application.get_env(:lightning, :usage_tracking)[:host]

      metrics = %{}

      Client.submit_metrics(metrics, host) |> create_report(metrics)
    end

    :ok
  end

  defp find_configuration do
    with nil <- Repo.one(Configuration) do
      Repo.insert!(%Configuration{})
    end
  end

  defp create_report(:ok, metrics) do
    %Report{data: metrics, submitted: true, submitted_at: DateTime.utc_now()}
    |> Repo.insert()
  end

  defp create_report(:error, metrics) do
    %Report{data: metrics} |> Repo.insert()
  end
end
