defmodule Lightning.UsageTrackingTest do
  use Lightning.DataCase

  alias Lightning.Repo
  alias Lightning.UsageTracking
  alias Lightning.UsageTracking.DailyReportConfiguration
  alias Lightning.UsageTracking.ReportWorker

  describe ".enable_daily_report/1 - no configuration exists" do
    setup do
      {:ok, tracking_enabled_at, _offset} =
        DateTime.from_iso8601("2024-03-01T18:23:23.000000Z")

      start_reporting_after = Date.from_iso8601!("2024-03-01")

      %{
        tracking_enabled_at: tracking_enabled_at,
        start_reporting_after: start_reporting_after
      }
    end

    test "creates record", %{
      tracking_enabled_at: tracking_enabled_at,
      start_reporting_after: start_reporting_after
    } do
      UsageTracking.enable_daily_report(tracking_enabled_at)

      report_config = Repo.one!(DailyReportConfiguration)

      assert %{
               tracking_enabled_at: ^tracking_enabled_at,
               start_reporting_after: ^start_reporting_after
             } = report_config
    end

    test "returns the configuration", %{
      tracking_enabled_at: tracking_enabled_at,
      start_reporting_after: start_reporting_after
    } do
      report_config = UsageTracking.enable_daily_report(tracking_enabled_at)

      assert %DailyReportConfiguration{
               tracking_enabled_at: ^tracking_enabled_at,
               start_reporting_after: ^start_reporting_after
             } = report_config
    end
  end

  describe ".enable_daily_report/1 - configuration exists with populated dates" do
    setup do
      {:ok, tracking_enabled_at, _offset} =
        DateTime.from_iso8601("2024-03-01T18:23:23.000000Z")

      {:ok, existing_tracking_enabled_at, _offset} =
        DateTime.from_iso8601("2024-02-01T10:10:10.000000Z")

      existing_start_reporting_after = Date.from_iso8601!("2024-02-01")

      %{
        tracking_enabled_at: tracking_enabled_at,
        existing_start_reporting_after: existing_start_reporting_after,
        existing_tracking_enabled_at: existing_tracking_enabled_at
      }
    end

    test "does not update the record", %{
      tracking_enabled_at: tracking_enabled_at,
      existing_tracking_enabled_at: existing_tracking_enabled_at,
      existing_start_reporting_after: existing_start_reporting_after
    } do
      insert(
        :usage_tracking_daily_report_configuration,
        tracking_enabled_at: existing_tracking_enabled_at,
        start_reporting_after: existing_start_reporting_after
      )

      UsageTracking.enable_daily_report(tracking_enabled_at)

      report_config = Repo.one!(DailyReportConfiguration)

      assert %{
               tracking_enabled_at: ^existing_tracking_enabled_at,
               start_reporting_after: ^existing_start_reporting_after
             } = report_config
    end

    test "returns the config", %{
      tracking_enabled_at: tracking_enabled_at,
      existing_tracking_enabled_at: existing_tracking_enabled_at,
      existing_start_reporting_after: existing_start_reporting_after
    } do
      %DailyReportConfiguration{
        tracking_enabled_at: existing_tracking_enabled_at,
        start_reporting_after: existing_start_reporting_after
      }
      |> Repo.insert!()

      report_config = UsageTracking.enable_daily_report(tracking_enabled_at)

      assert %{
               tracking_enabled_at: ^existing_tracking_enabled_at,
               start_reporting_after: ^existing_start_reporting_after
             } = report_config
    end
  end

  describe ".enable_daily_report/1 - record exists but dates are not populated" do
    setup do
      {:ok, tracking_enabled_at, _offset} =
        DateTime.from_iso8601("2024-03-01T18:23:23.000000Z")

      start_reporting_after = Date.from_iso8601!("2024-03-01")

      %{
        tracking_enabled_at: tracking_enabled_at,
        start_reporting_after: start_reporting_after
      }
    end

    test "updates the record", %{
      tracking_enabled_at: tracking_enabled_at,
      start_reporting_after: start_reporting_after
    } do
      %DailyReportConfiguration{} |> Repo.insert!()

      UsageTracking.enable_daily_report(tracking_enabled_at)

      report_config = Repo.one!(DailyReportConfiguration)

      assert %{
               tracking_enabled_at: ^tracking_enabled_at,
               start_reporting_after: ^start_reporting_after
             } = report_config
    end

    test "returns the updated record", %{
      tracking_enabled_at: tracking_enabled_at,
      start_reporting_after: start_reporting_after
    } do
      %DailyReportConfiguration{} |> Repo.insert!()

      report_config = UsageTracking.enable_daily_report(tracking_enabled_at)

      assert %{
               tracking_enabled_at: ^tracking_enabled_at,
               start_reporting_after: ^start_reporting_after
             } = report_config
    end
  end

  describe ".disable_daily_report/1 - record exists" do
    setup do
      {:ok, existing_tracking_enabled_at, _offset} =
        DateTime.from_iso8601("2024-02-01T10:10:10.000000Z")

      existing_start_reporting_after = Date.from_iso8601!("2024-02-01")

      %{
        existing_start_reporting_after: existing_start_reporting_after,
        existing_tracking_enabled_at: existing_tracking_enabled_at
      }
    end

    test "sets the dates to nil", %{
      existing_tracking_enabled_at: existing_tracking_enabled_at,
      existing_start_reporting_after: existing_start_reporting_after
    } do
      %DailyReportConfiguration{
        tracking_enabled_at: existing_tracking_enabled_at,
        start_reporting_after: existing_start_reporting_after
      }
      |> Repo.insert!()

      UsageTracking.disable_daily_report()

      report_config = Repo.one!(DailyReportConfiguration)

      assert %{tracking_enabled_at: nil, start_reporting_after: nil} =
               report_config
    end

    test "returns the updated record", %{
      existing_tracking_enabled_at: existing_tracking_enabled_at,
      existing_start_reporting_after: existing_start_reporting_after
    } do
      %DailyReportConfiguration{
        tracking_enabled_at: existing_tracking_enabled_at,
        start_reporting_after: existing_start_reporting_after
      }
      |> Repo.insert!()

      report_config = UsageTracking.disable_daily_report()

      assert %{tracking_enabled_at: nil, start_reporting_after: nil} =
               report_config
    end
  end

  describe ".disable_daily_report/1 - no record exists" do
    test "returns nil" do
      assert UsageTracking.disable_daily_report() == nil
    end
  end

  describe ".start_reporting_after/1 - enabled configuration exists" do
    setup do
      %DailyReportConfiguration{
        tracking_enabled_at: DateTime.utc_now(),
        start_reporting_after: ~D[2024-03-01]
      }
      |> Repo.insert!()

      %{date: ~D[2024-03-05]}
    end

    test "updates the start_reporting_after date", %{date: date} do
      UsageTracking.start_reporting_after(date)

      assert %{start_reporting_after: ^date} =
               Repo.one!(DailyReportConfiguration)
    end

    test "returns :ok", %{date: date} do
      assert UsageTracking.start_reporting_after(date) == :ok
    end
  end

  describe ".start_reporting_after/1 - no configuration exists" do
    setup do
      %{date: ~D[2024-03-05]}
    end

    test "does nothing", %{date: date} do
      UsageTracking.start_reporting_after(date)

      assert Repo.one(DailyReportConfiguration) == nil
    end

    test "returns :error", %{date: date} do
      assert UsageTracking.start_reporting_after(date) == :error
    end
  end

  describe ".start_reporting_after/1 - disabled configuration exists" do
    setup do
      existing_date = ~D[2024-03-01]

      %DailyReportConfiguration{
        tracking_enabled_at: nil,
        start_reporting_after: existing_date
      }
      |> Repo.insert!()

      %{date: ~D[2024-03-05], existing_date: existing_date}
    end

    test "does not update the record", config do
      %{date: date, existing_date: existing_date} = config

      UsageTracking.start_reporting_after(date)

      assert %{
               tracking_enabled_at: nil,
               start_reporting_after: ^existing_date
             } = Repo.one!(DailyReportConfiguration)
    end

    test "returns :error", %{date: date} do
      assert UsageTracking.start_reporting_after(date) == :error
    end
  end

  describe ".reportable_dates/1" do
    setup do
      %{batch_size: 10}
    end

    test "returns range of reportable dates between the boundary dates", %{
      batch_size: batch_size
    } do
      start_after = ~D[2024-02-12]
      today = ~D[2024-02-20]

      expected_dates = [
        ~D[2024-02-13],
        ~D[2024-02-14],
        ~D[2024-02-15],
        ~D[2024-02-16],
        ~D[2024-02-17],
        ~D[2024-02-18],
        ~D[2024-02-19]
      ]

      dates = UsageTracking.reportable_dates(start_after, today, batch_size)

      assert dates == expected_dates
    end

    test "returns empty list if no reportable dates", %{
      batch_size: batch_size
    } do
      start_after = ~D[2024-02-19]
      today = ~D[2024-02-20]

      assert UsageTracking.reportable_dates(start_after, today, batch_size) == []
    end

    test "returns empty list if start_after is today", %{
      batch_size: batch_size
    } do
      start_after = ~D[2024-02-20]
      today = ~D[2024-02-20]

      assert UsageTracking.reportable_dates(start_after, today, batch_size) == []
    end

    test "returns empty list if start_after is after today", %{
      batch_size: batch_size
    } do
      start_after = ~D[2024-02-21]
      today = ~D[2024-02-20]

      assert UsageTracking.reportable_dates(start_after, today, batch_size) == []
    end

    test "excludes any reportable days for which reports exist", %{
      batch_size: batch_size
    } do
      start_after = ~D[2024-02-12]
      today = ~D[2024-02-20]

      _before_start =
        insert(:usage_tracking_report, report_date: ~D[2024-02-11])

      _exclude_date_1 =
        insert(:usage_tracking_report, report_date: ~D[2024-02-17])

      _exclude_date_2 =
        insert(:usage_tracking_report, report_date: ~D[2024-02-14])

      _nil_date =
        insert(:usage_tracking_report, report_date: nil)

      expected_dates = [
        ~D[2024-02-13],
        ~D[2024-02-15],
        ~D[2024-02-16],
        ~D[2024-02-18],
        ~D[2024-02-19]
      ]

      dates = UsageTracking.reportable_dates(start_after, today, batch_size)

      assert dates == expected_dates
    end

    test "number of reportable days is constrained by batch size" do
      start_after = ~D[2024-02-12]
      today = ~D[2024-02-20]
      batch_size = 3

      # Use existing reports to ensure that the batching is applied to the output
      # dates and not the input dates. The presence of these two entries will
      # remove the first two dates from consideration for batching.
      _batch_padding_1 =
        insert(:usage_tracking_report, report_date: ~D[2024-02-13])

      _batch_padding_2 =
        insert(:usage_tracking_report, report_date: ~D[2024-02-14])

      expected_dates = [
        ~D[2024-02-15],
        ~D[2024-02-16],
        ~D[2024-02-17]
      ]

      dates = UsageTracking.reportable_dates(start_after, today, batch_size)

      assert dates == expected_dates
    end
  end

  describe ".enqueue_reports/3 - tracking is enabled" do
    setup do
      reference_time = DateTime.utc_now()
      range_in_days = 7
      batch_size = 10
      enabled_at = DateTime.add(reference_time, -range_in_days, :day)

      first_report_date =
        enabled_at
        |> DateTime.add(1, :day)
        |> DateTime.to_date()

      last_report_date =
        reference_time
        |> DateTime.add(-1, :day)
        |> DateTime.to_date()

      reportable_dates =
        first_report_date
        |> Date.range(last_report_date)
        |> Enum.to_list()

      %{
        batch_size: batch_size,
        enabled_at: enabled_at,
        range_in_days: range_in_days,
        reference_time: reference_time,
        reportable_dates: reportable_dates
      }
    end

    test "enables the configuration", %{
      reference_time: reference_time,
      batch_size: batch_size
    } do
      UsageTracking.enqueue_reports(true, reference_time, batch_size)

      %{tracking_enabled_at: enabled_at} = Repo.one(DailyReportConfiguration)

      assert DateTime.diff(DateTime.utc_now(), enabled_at, :second) < 5
    end

    test "enqueues jobs to process outstanding days", %{
      batch_size: batch_size,
      enabled_at: enabled_at,
      reference_time: reference_time,
      reportable_dates: reportable_dates
    } do
      UsageTracking.enable_daily_report(enabled_at)

      Oban.Testing.with_testing_mode(:manual, fn ->
        UsageTracking.enqueue_reports(true, reference_time, batch_size)
      end)

      for date <- reportable_dates do
        assert_enqueued(worker: ReportWorker, args: %{date: date})
      end
    end

    test "does not enqueue more than the batch size", %{
      enabled_at: enabled_at,
      reference_time: reference_time,
      reportable_dates: reportable_dates
    } do
      batch_size = length(reportable_dates) - 2
      included_dates = reportable_dates |> Enum.take(batch_size)
      excluded_dates = reportable_dates |> Enum.take(-2)

      UsageTracking.enable_daily_report(enabled_at)

      Oban.Testing.with_testing_mode(:manual, fn ->
        UsageTracking.enqueue_reports(true, reference_time, batch_size)

        for date <- included_dates do
          assert_enqueued(worker: ReportWorker, args: %{date: date})
        end

        for date <- excluded_dates do
          refute_enqueued(worker: ReportWorker, args: %{date: date})
        end
      end)
    end

    test "updates the config based on reportable dates", %{
      batch_size: batch_size,
      enabled_at: enabled_at,
      reference_time: reference_time,
      reportable_dates: reportable_dates
    } do
      [report_date_1 | [report_date_2 | _other_dates]] = reportable_dates

      # Add some existing reports so that the start_reporting_after will take
      # these into account
      insert(:usage_tracking_report, report_date: report_date_1)
      insert(:usage_tracking_report, report_date: report_date_2)

      UsageTracking.enable_daily_report(enabled_at)

      Oban.Testing.with_testing_mode(:manual, fn ->
        UsageTracking.enqueue_reports(true, reference_time, batch_size)
      end)

      report_config = DailyReportConfiguration |> Repo.one!()

      assert report_config.start_reporting_after == report_date_2
    end

    test "does not update config if there are no reportable dates", %{
      batch_size: batch_size,
      reference_time: reference_time
    } do
      enabled_at = DateTime.add(reference_time, -1, :day)

      %{start_reporting_after: existing_date} =
        UsageTracking.enable_daily_report(enabled_at)

      Oban.Testing.with_testing_mode(:manual, fn ->
        UsageTracking.enqueue_reports(true, reference_time, batch_size)
      end)

      report_config = DailyReportConfiguration |> Repo.one!()

      assert report_config.start_reporting_after == existing_date
    end

    test "returns :ok", %{
      batch_size: batch_size,
      reference_time: reference_time
    } do
      assert UsageTracking.enqueue_reports(
               true,
               reference_time,
               batch_size
             ) == :ok
    end
  end

  describe ".enqueue_reports/3 - tracking is disabled" do
    setup do
      batch_size = 10
      reference_time = DateTime.utc_now()

      UsageTracking.enable_daily_report(reference_time)

      %{
        batch_size: batch_size,
        reference_time: reference_time
      }
    end

    test "disables the configuration", %{
      batch_size: batch_size,
      reference_time: reference_time
    } do
      assert UsageTracking.enqueue_reports(
               false,
               reference_time,
               batch_size
             )

      %{tracking_enabled_at: nil} = Repo.one(DailyReportConfiguration)
    end

    test "returns :ok", %{
      batch_size: batch_size,
      reference_time: reference_time
    } do
      assert UsageTracking.enqueue_reports(
               false,
               reference_time,
               batch_size
             ) == :ok
    end
  end
end
