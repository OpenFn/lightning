defmodule Lightning.UsageTracking.DayWorkerTest do
  use Lightning.DataCase

  import Lightning.ApplicationHelpers, only: [put_temporary_env: 3]

  alias Lightning.Repo
  alias Lightning.UsageTracking
  alias Lightning.UsageTracking.DailyReportConfiguration
  alias Lightning.UsageTracking.DayWorker

  describe "tracking is enabled" do
    setup do
      put_temporary_env(:lightning, :usage_tracking, enabled: true)
    end

    test "enables the configuration" do
      DayWorker.perform(%{})

      %{tracking_enabled_at: enabled_at} = Repo.one(DailyReportConfiguration)

      assert DateTime.diff(DateTime.utc_now(), enabled_at, :second) < 5
    end

    test "returns :ok" do
      assert DayWorker.perform(%{}) == :ok
    end
  end

  describe "tracking is not enabled" do
    setup do
      put_temporary_env(:lightning, :usage_tracking, enabled: false)
    end

    test "disables the configuration" do
      UsageTracking.enable_daily_report(DateTime.utc_now())

      DayWorker.perform(%{})

      assert %{tracking_enabled_at: nil} = Repo.one(DailyReportConfiguration)
    end

    test "returns :ok" do
      assert DayWorker.perform(%{}) == :ok
    end
  end
end
