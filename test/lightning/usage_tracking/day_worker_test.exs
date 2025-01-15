defmodule Lightning.UsageTracking.DayWorkerTest do
  use Lightning.DataCase, async: true

  import Mox

  alias Lightning.Repo
  alias Lightning.UsageTracking
  alias Lightning.UsageTracking.DailyReportConfiguration
  alias Lightning.UsageTracking.DayWorker
  alias Lightning.UsageTracking.ReportWorker

  @batch_size 4
  @range_in_days 7

  describe "perform/1 without reference time & tracking enabled" do
    # These tests have some tolerance built in when dealing with times
    # to prevent the tests flickering - e.g if .utc_now() changes during
    # the execution of the test
    setup do
      stub(Lightning.MockConfig, :usage_tracking_enabled?, fn ->
        true
      end)

      :ok
    end

    test "enables the configuration" do
      perform_job(DayWorker, %{batch_size: @batch_size})

      %{tracking_enabled_at: enabled_at} = Repo.one(DailyReportConfiguration)

      assert DateTime.diff(DateTime.utc_now(), enabled_at, :second) < 3
    end

    test "does not enqueue more jobs than the batch size" do
      assert @batch_size < @range_in_days - 1

      enabled_at = DateTime.add(DateTime.utc_now(), -@range_in_days, :day)

      UsageTracking.enable_daily_report(enabled_at)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok == perform_job(DayWorker, %{batch_size: @batch_size})
      end)

      assert length(all_enqueued(worker: ReportWorker)) == @batch_size
    end
  end

  describe "perform/1 without reference time passed in - tracking is disabled" do
    setup do
      stub(Lightning.MockConfig, :usage_tracking_enabled?, fn -> false end)

      UsageTracking.enable_daily_report(DateTime.utc_now())

      :ok
    end

    test "disables the configuration" do
      assert :ok == perform_job(DayWorker, %{batch_size: @batch_size})
      assert %{tracking_enabled_at: nil} = Repo.one(DailyReportConfiguration)
    end
  end
end
