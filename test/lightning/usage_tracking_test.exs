defmodule Lightning.UsageTrackingTest do
  use Lightning.DataCase, async: false

  import Mock

  alias Lightning.Repo
  alias Lightning.UsageTracking
  alias Lightning.UsageTracking.Client
  alias Lightning.UsageTracking.DailyReportConfiguration
  alias Lightning.UsageTracking.GithubClient
  alias Lightning.UsageTracking.Report
  alias Lightning.UsageTracking.ReportData
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
    # NOTE: When modifying these dates, ensure that the range spans a year
    # boundary to better detect date sorting issues
    setup do
      %{batch_size: 10}
    end

    test "returns range of reportable dates between the boundary dates", %{
      batch_size: batch_size
    } do
      start_after = ~D[2023-12-28]
      today = ~D[2024-01-05]

      expected_dates = [
        ~D[2023-12-29],
        ~D[2023-12-30],
        ~D[2023-12-31],
        ~D[2024-01-01],
        ~D[2024-01-02],
        ~D[2024-01-03],
        ~D[2024-01-04]
      ]

      dates = UsageTracking.reportable_dates(start_after, today, batch_size)

      assert dates == expected_dates
    end

    test "returns empty list if no reportable dates", %{
      batch_size: batch_size
    } do
      start_after = ~D[2024-01-04]
      today = ~D[2024-01-05]

      assert UsageTracking.reportable_dates(start_after, today, batch_size) == []
    end

    test "returns empty list if start_after is today", %{
      batch_size: batch_size
    } do
      start_after = ~D[2024-01-05]
      today = ~D[2024-01-05]

      assert UsageTracking.reportable_dates(start_after, today, batch_size) == []
    end

    test "returns empty list if start_after is after today", %{
      batch_size: batch_size
    } do
      start_after = ~D[2024-01-06]
      today = ~D[2024-01-05]

      assert UsageTracking.reportable_dates(start_after, today, batch_size) == []
    end

    test "excludes any reportable days for which reports exist", %{
      batch_size: batch_size
    } do
      start_after = ~D[2023-12-28]
      today = ~D[2024-01-05]

      _before_start =
        insert(:usage_tracking_report, report_date: ~D[2023-12-27])

      _exclude_date_1 =
        insert(:usage_tracking_report, report_date: ~D[2024-01-03])

      _exclude_date_2 =
        insert(:usage_tracking_report, report_date: ~D[2024-01-01])

      _nil_date =
        insert(:usage_tracking_report, report_date: nil)

      expected_dates = [
        ~D[2023-12-29],
        ~D[2023-12-30],
        ~D[2023-12-31],
        ~D[2024-01-02],
        ~D[2024-01-04]
      ]

      dates = UsageTracking.reportable_dates(start_after, today, batch_size)

      assert dates == expected_dates
    end

    test "number of reportable days is constrained by batch size" do
      start_after = ~D[2023-12-28]
      today = ~D[2024-01-05]
      batch_size = 3

      # Use existing reports to ensure that the batching is applied to the output
      # dates and not the input dates. The presence of these two entries will
      # remove the first two dates from consideration for batching.
      _batch_padding_1 =
        insert(:usage_tracking_report, report_date: ~D[2023-12-29])

      _batch_padding_2 =
        insert(:usage_tracking_report, report_date: ~D[2023-12-30])

      expected_dates = [
        ~D[2023-12-31],
        ~D[2024-01-01],
        ~D[2024-01-02]
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

  describe "find_enabled_daily_report_config/0" do
    test "returns existing config if it is enabled" do
      expected_config = UsageTracking.enable_daily_report(DateTime.utc_now())

      returned_config = UsageTracking.find_enabled_daily_report_config()

      assert returned_config == expected_config
    end

    test "returns nil if the config exists but is disabled" do
      UsageTracking.enable_daily_report(DateTime.utc_now())
      UsageTracking.disable_daily_report()

      assert UsageTracking.find_enabled_daily_report_config() == nil
    end

    test "returns nil if the config does not exist" do
      assert UsageTracking.find_enabled_daily_report_config() == nil
    end
  end

  describe ".insert_report - cleartext uuids disabled" do
    setup_with_mocks([
      {GithubClient, [], [open_fn_commit?: fn _ -> true end]}
    ]) do
      cleartext_uuids_enabled = false

      date = ~D[2024-02-05]

      report_config =
        UsageTracking.enable_daily_report(DateTime.utc_now())

      %{
        instance: expected_instance_data,
        report_date: expected_report_date
      } =
        report_config
        |> ReportData.generate(cleartext_uuids_enabled, date)
        |> Map.take([:instance, :report_date])

      %{
        cleartext_uuids_enabled: cleartext_uuids_enabled,
        date: date,
        expected_instance_data: expected_instance_data,
        expected_report_date: expected_report_date,
        report_config: report_config
      }
    end

    test "inserts an unsubmitted report instance", %{
      cleartext_uuids_enabled: cleartext_uuids_enabled,
      date: date,
      expected_instance_data: instance_data,
      expected_report_date: expected_report_date,
      report_config: report_config
    } do
      UsageTracking.insert_report(report_config, cleartext_uuids_enabled, date)

      expected_instance_data =
        instance_data
        |> Jason.encode!()
        |> Jason.decode!()

      expected_date_string = Date.to_iso8601(expected_report_date)

      report = Repo.one(Report)

      assert %{
               submitted: false,
               submitted_at: nil,
               report_date: ^expected_report_date,
               submission_status: :pending
             } = report

      assert %{
               "instance" => ^expected_instance_data,
               "report_date" => ^expected_date_string
             } = report.data
    end

    test "returns the report instance", %{
      cleartext_uuids_enabled: cleartext_uuids_enabled,
      date: date,
      expected_instance_data: expected_instance_data,
      expected_report_date: expected_report_date,
      report_config: report_config
    } do
      {:ok, report} =
        UsageTracking.insert_report(report_config, cleartext_uuids_enabled, date)

      assert %{id: inserted_id} = Repo.one(Report)

      assert %{
               id: ^inserted_id,
               submitted: false,
               submitted_at: nil,
               report_date: ^date,
               submission_status: :pending
             } = report

      assert %{
               instance: ^expected_instance_data,
               report_date: ^expected_report_date
             } = report.data
    end
  end

  describe ".insert_report - cleartext uuids enabled" do
    setup_with_mocks([
      {GithubClient, [], [open_fn_commit?: fn _ -> true end]}
    ]) do
      cleartext_uuids_enabled = false

      date = ~D[2024-02-05]

      report_config =
        UsageTracking.enable_daily_report(DateTime.utc_now())

      %{
        instance: expected_instance_data,
        report_date: expected_report_date
      } =
        report_config
        |> ReportData.generate(cleartext_uuids_enabled, date)
        |> Map.take([:instance, :report_date])

      %{
        cleartext_uuids_enabled: cleartext_uuids_enabled,
        date: date,
        expected_instance_data: expected_instance_data,
        expected_report_date: expected_report_date,
        report_config: report_config
      }
    end

    test "inserts an unsubmitted report instance", %{
      cleartext_uuids_enabled: cleartext_uuids_enabled,
      date: date,
      expected_instance_data: instance_data,
      expected_report_date: expected_report_date,
      report_config: report_config
    } do
      UsageTracking.insert_report(report_config, cleartext_uuids_enabled, date)

      expected_instance_data =
        instance_data
        |> Jason.encode!()
        |> Jason.decode!()

      expected_date_string = Date.to_iso8601(expected_report_date)

      report = Repo.one(Report)

      assert %{
               submitted: false,
               submitted_at: nil,
               report_date: ^expected_report_date,
               submission_status: :pending
             } = report

      assert %{
               "instance" => ^expected_instance_data,
               "report_date" => ^expected_date_string
             } = report.data
    end

    test "returns the report instance", %{
      cleartext_uuids_enabled: cleartext_uuids_enabled,
      date: date,
      expected_instance_data: expected_instance_data,
      expected_report_date: expected_report_date,
      report_config: report_config
    } do
      {:ok, report} =
        UsageTracking.insert_report(report_config, cleartext_uuids_enabled, date)

      assert %{id: inserted_id} = Repo.one(Report)

      assert %{
               id: ^inserted_id,
               submitted: false,
               submitted_at: nil,
               report_date: ^date,
               submission_status: :pending
             } = report

      assert %{
               instance: ^expected_instance_data,
               report_date: ^expected_report_date
             } = report.data
    end
  end

  describe ".update_report_submission - successful" do
    setup do
      report =
        insert(
          :usage_tracking_report,
          submitted: false,
          submitted_at: nil,
          submission_status: :pending
        )

      %{report: report}
    end

    test "updates submission fields if submission was successful", %{
      report: report
    } do
      UsageTracking.update_report_submission!(:ok, report)

      assert %{
               submitted: true,
               submitted_at: submitted_at,
               submission_status: :success
             } = Repo.get!(Report, report.id)

      assert DateTime.diff(DateTime.utc_now(), submitted_at, :second) < 2
    end

    test "returns the updated report", %{
      report: report
    } do
      updated_report = UsageTracking.update_report_submission!(:ok, report)

      assert %{
               submitted: true,
               submitted_at: submitted_at,
               submission_status: :success
             } = updated_report

      assert DateTime.diff(DateTime.utc_now(), submitted_at, :second) < 2
    end
  end

  describe ".update_report_submission - unsuccessful" do
    setup do
      report =
        insert(
          :usage_tracking_report,
          submitted: false,
          submitted_at: DateTime.utc_now(),
          submission_status: :pending
        )

      %{report: report}
    end

    test "updates the submission fields to indicate a failed submission", %{
      report: report
    } do
      UsageTracking.update_report_submission!(:error, report)

      assert %{
               submitted: false,
               submitted_at: nil,
               submission_status: :failure
             } = Repo.get!(Report, report.id)
    end

    test "returns the updated report", %{
      report: report
    } do
      updated_report = UsageTracking.update_report_submission!(:error, report)

      assert %{
               submitted: false,
               submitted_at: nil,
               submission_status: :failure
             } = updated_report
    end
  end

  describe ".lightning_version - commit is an openfn commit" do
    setup_with_mocks([
      {
        GithubClient,
        [],
        [
          open_fn_commit?: fn
            "abc123" -> true
            other_sha -> flunk("Commit sha #{other_sha} passed to GithubClient")
          end
        ]
      }
    ]) do
      commit = "abc123"
      spec_version = "v#{Application.spec(:lightning, :vsn)}"

      %{
        commit: commit,
        spec_version: spec_version
      }
    end

    test "indicates when the image is `edge`", %{
      commit: commit,
      spec_version: spec_version
    } do
      set_release(branch: "ignored", commit: commit, image_tag: "edge")

      assert UsageTracking.lightning_version() ==
               "#{spec_version}:edge:#{commit}"
    end

    test "indicates when the image matches the spec version", %{
      commit: commit,
      spec_version: spec_version
    } do
      set_release(branch: "ignored", commit: commit, image_tag: spec_version)

      assert UsageTracking.lightning_version() ==
               "#{spec_version}:match:#{commit}"
    end

    test "indicates when the image is neither version nor `edge`", %{
      commit: commit,
      spec_version: spec_version
    } do
      set_release(branch: "ignored", commit: commit, image_tag: "unique")

      assert UsageTracking.lightning_version() ==
               "#{spec_version}:other:#{commit}"
    end
  end

  describe ".lightning_version/0 - commit is not an openfn commit" do
    setup_with_mocks([
      {
        GithubClient,
        [],
        [
          open_fn_commit?: fn
            "abc123" -> false
            other_sha -> flunk("Commit sha #{other_sha} passed to GithubClient")
          end
        ]
      }
    ]) do
      commit = "abc123"
      spec_version = "v#{Application.spec(:lightning, :vsn)}"

      %{
        commit: commit,
        spec_version: spec_version
      }
    end

    test "indicates when the image is `edge`", %{
      commit: commit,
      spec_version: version
    } do
      set_release(branch: "ignored", commit: commit, image_tag: "edge")

      assert UsageTracking.lightning_version() == "#{version}:edge:sanitised"
    end

    test "indicates when the image matches the spec version", %{
      commit: commit,
      spec_version: spec_version
    } do
      set_release(branch: "ignored", commit: commit, image_tag: spec_version)

      assert UsageTracking.lightning_version() ==
               "#{spec_version}:match:sanitised"
    end

    test "indicates when the image is neither version nor `edge`", %{
      commit: commit,
      spec_version: spec_version
    } do
      set_release(branch: "ignored", commit: commit, image_tag: "unique")

      assert UsageTracking.lightning_version() ==
               "#{spec_version}:other:sanitised"
    end
  end

  describe ".submit_report/2" do
    setup do
      report =
        insert(
          :usage_tracking_report,
          data: %{foo: "bar"},
          submission_status: :pending,
          submitted: false,
          submitted_at: nil
        )

      %{host: "https://impact.openfn.org", report: report}
    end

    test "submits data to the impact tracker", %{
      host: host,
      report: report
    } do
      with_mock Client,
        submit_metrics: fn _metrics, _host -> :ok end do
        UsageTracking.submit_report(report, host)

        assert_called(Client.submit_metrics(report.data, host))
      end
    end

    test "updates report to indicate successful submission", %{
      host: host,
      report: report
    } do
      with_mock Client,
        submit_metrics: fn _metrics, _host -> :ok end do
        UsageTracking.submit_report(report, host)
      end

      assert %{
               submitted: true,
               submitted_at: submitted_at,
               submission_status: :success
             } = Repo.get!(Report, report.id)

      assert DateTime.diff(DateTime.utc_now(), submitted_at, :second) < 2
    end

    test "updates report to indicate unsuccessful submission", %{
      host: host,
      report: report
    } do
      with_mock Client,
        submit_metrics: fn _metrics, _host -> :error end do
        UsageTracking.submit_report(report, host)
      end

      assert %{
               submitted: false,
               submitted_at: nil,
               submission_status: :failure
             } = Repo.get!(Report, report.id)
    end

    test "returns the updated report", %{
      host: host,
      report: report
    } do
      updated_report =
        with_mock Client,
          submit_metrics: fn _metrics, _host -> :ok end do
          UsageTracking.submit_report(report, host)
        end

      assert %{
               submitted: true,
               submitted_at: submitted_at,
               submission_status: :success
             } = updated_report

      assert DateTime.diff(DateTime.utc_now(), submitted_at, :second) < 2
    end
  end

  defp set_release(values) do
    original = Lightning.API.release()
    allowed_keys = Map.keys(original)

    override =
      values
      |> Enum.reject(fn {k, _} -> k not in allowed_keys end)
      |> Map.new()

    Mox.stub(LightningMock, :release, fn -> Map.merge(original, override) end)
  end
end
