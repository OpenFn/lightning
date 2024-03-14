defmodule Lightning.UsageTracking do
  @moduledoc """
  The UsageTracking context.
  """
  alias Lightning.Repo
  alias Lightning.UsageTracking.DailyReportConfiguration

  def enable_daily_report(enabled_at) do
    start_reporting_after = DateTime.to_date(enabled_at)

    case Repo.one(DailyReportConfiguration) do
      config = %{tracking_enabled_at: nil, start_reporting_after: nil} ->
        config
        |> DailyReportConfiguration.changeset(%{
          tracking_enabled_at: enabled_at,
          start_reporting_after: start_reporting_after
        })
        |> Repo.update!()

      nil ->
        %DailyReportConfiguration{
          tracking_enabled_at: enabled_at,
          start_reporting_after: start_reporting_after
        }
        |> Repo.insert!()

      config ->
        config
    end
  end

  def disable_daily_report do
    if config = Repo.one(DailyReportConfiguration) do
      config
      |> DailyReportConfiguration.changeset(%{
        tracking_enabled_at: nil,
        start_reporting_after: nil
      })
      |> Repo.update!()
    end
  end
end
