defmodule Lightning.UsageTrackingTest do
  use Lightning.DataCase

  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.UsageTracking
  alias Lightning.UsageTracking.DailyReportConfiguration
  alias Lightning.Projects.Project
  alias Lightning.UsageTracking.ReportWorker

  require Run

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
      insert(
        :usage_tracking_daily_report_configuration,
        tracking_enabled_at: existing_tracking_enabled_at,
        start_reporting_after: existing_start_reporting_after
      )

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
      insert(:usage_tracking_daily_report_configuration)

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
      insert(:usage_tracking_daily_report_configuration)

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
      insert(
        :usage_tracking_daily_report_configuration,
        tracking_enabled_at: existing_tracking_enabled_at,
        start_reporting_after: existing_start_reporting_after
      )

      UsageTracking.disable_daily_report()

      report_config = Repo.one!(DailyReportConfiguration)

      assert %{tracking_enabled_at: nil, start_reporting_after: nil} =
               report_config
    end

    test "returns the updated record", %{
      existing_tracking_enabled_at: existing_tracking_enabled_at,
      existing_start_reporting_after: existing_start_reporting_after
    } do
      insert(
        :usage_tracking_daily_report_configuration,
        tracking_enabled_at: existing_tracking_enabled_at,
        start_reporting_after: existing_start_reporting_after
      )

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
      insert(
        :usage_tracking_daily_report_configuration,
        tracking_enabled_at: DateTime.utc_now(),
        start_reporting_after: ~D[2024-03-01]
      )

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

      insert(
        :usage_tracking_daily_report_configuration,
        tracking_enabled_at: nil,
        start_reporting_after: existing_date
      )

      %{date: ~D[2024-03-05], existing_date: existing_date}
    end

    test "does not update the record", %{
      date: date,
      existing_date: existing_date
    } do
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

  describe ".find_enabled_daily_report_config/0" do
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

  describe ".find_eligible_projects" do
    setup do
      %{date: ~D[2024-02-05]}
    end

    test "returns all projects created before the date", %{date: date} do
      eligible_project_1 =
        insert(:project, inserted_at: ~U[2024-02-05 23:59:58Z])

      eligible_project_2 =
        insert(:project, inserted_at: ~U[2024-02-04 23:59:59Z])

      ineligible_project_1 =
        insert(:project, inserted_at: ~U[2024-02-06 00:00:00Z])

      ineligible_project_2 =
        insert(:project, inserted_at: ~U[2024-02-06 00:00:01Z])

      result = UsageTracking.find_eligible_projects(date)

      assert result |> contains?(eligible_project_1)
      assert result |> contains?(eligible_project_2)
      refute result |> contains?(ineligible_project_1)
      refute result |> contains?(ineligible_project_2)
    end
  end

  describe ".generate_metrics/3 (project) - cleartext disabled" do
    setup do
      generate_metrics_project_setup() |> Map.merge(%{enabled: false})
    end

    test "includes the hashed project id", %{
      date: date,
      enabled: enabled,
      hashed_id: hashed_id,
      project: project
    } do
      assert %{
               hashed_uuid: ^hashed_id
             } = UsageTracking.generate_metrics(project, enabled, date)
    end

    test "excludes the cleartext uuid", %{
      date: date,
      enabled: enabled,
      project: project
    } do
      assert %{
               cleartext_uuid: nil
             } = UsageTracking.generate_metrics(project, enabled, date)
    end

    test "includes the number of project users", %{
      active_user_count: active_user_count,
      date: date,
      enabled: enabled,
      project: project
    } do
      user_count = active_user_count + 1

      assert %{
               no_of_users: ^user_count
             } = UsageTracking.generate_metrics(project, enabled, date)
    end

    test "includes the number of active users", %{
      active_user_count: active_user_count,
      date: date,
      enabled: enabled,
      project: project
    } do
      assert %{
               no_of_active_users: ^active_user_count
             } = UsageTracking.generate_metrics(project, enabled, date)
    end

    test "includes data for workflows existing on or before date", %{
      date: date,
      eligible_workflow_1: eligible_workflow_1,
      eligible_workflow_2: eligible_workflow_2,
      enabled: enabled,
      ineligible_workflow: ineligible_workflow,
      project: project
    } do
      %{workflows: workflows} =
        UsageTracking.generate_metrics(project, enabled, date)

      workflows
      |> assert_metrics(
        target: eligible_workflow_1,
        cleartext_enabled: enabled,
        date: date
      )

      workflows
      |> assert_metrics(
        target: eligible_workflow_2,
        cleartext_enabled: enabled,
        date: date
      )

      workflows |> refute_metrics(target: ineligible_workflow)
    end
  end

  describe ".generate_metrics/3 (project) - cleartext enabled" do
    setup do
      generate_metrics_project_setup() |> Map.merge(%{enabled: true})
    end

    test "includes the hashed project id", %{
      date: date,
      enabled: enabled,
      hashed_id: hashed_id,
      project: project
    } do
      assert %{
               hashed_uuid: ^hashed_id
             } = UsageTracking.generate_metrics(project, enabled, date)
    end

    test "includes the cleartext uuid", %{
      date: date,
      enabled: enabled,
      project: project
    } do
      project_id = project.id

      assert %{
               cleartext_uuid: ^project_id
             } = UsageTracking.generate_metrics(project, enabled, date)
    end

    test "includes the number of project users", %{
      active_user_count: active_user_count,
      date: date,
      enabled: enabled,
      project: project
    } do
      user_count = active_user_count + 1

      assert %{
               no_of_users: ^user_count
             } = UsageTracking.generate_metrics(project, enabled, date)
    end

    test "includes the number of active users", %{
      active_user_count: active_user_count,
      date: date,
      enabled: enabled,
      project: project
    } do
      assert %{
               no_of_active_users: ^active_user_count
             } = UsageTracking.generate_metrics(project, enabled, date)
    end

    test "includes data for workflows existing on or before date", %{
      date: date,
      eligible_workflow_1: eligible_workflow_1,
      eligible_workflow_2: eligible_workflow_2,
      enabled: enabled,
      ineligible_workflow: ineligible_workflow,
      project: project
    } do
      %{workflows: workflows} =
        UsageTracking.generate_metrics(project, enabled, date)

      workflows
      |> assert_metrics(
        target: eligible_workflow_1,
        cleartext_enabled: enabled,
        date: date
      )

      workflows
      |> assert_metrics(
        target: eligible_workflow_2,
        cleartext_enabled: enabled,
        date: date
      )

      workflows |> refute_metrics(target: ineligible_workflow)
    end
  end

  describe "generate_metrics/3 (workflow) - cleartext disabled" do
    setup do
      generate_metrics_workflow_setup() |> Map.merge(%{enabled: false})
    end

    test "includes the hashed workflow uuid", %{
      date: date,
      enabled: enabled,
      hashed_uuid: hashed_uuid,
      workflow: workflow
    } do
      assert %{
               hashed_uuid: ^hashed_uuid
             } = UsageTracking.generate_metrics(workflow, enabled, date)
    end

    test "does not include the cleartext uuid", %{
      date: date,
      enabled: enabled,
      workflow: workflow
    } do
      assert %{
               cleartext_uuid: nil
             } = UsageTracking.generate_metrics(workflow, enabled, date)
    end

    test "includes the number of jobs", %{
      date: date,
      enabled: enabled,
      no_of_jobs: no_of_jobs,
      workflow: workflow
    } do
      assert %{
               no_of_jobs: ^no_of_jobs
             } = UsageTracking.generate_metrics(workflow, enabled, date)
    end

    test "includes the number of finished runs", %{
      date: date,
      enabled: enabled,
      no_of_runs: no_of_runs,
      workflow: workflow
    } do
      assert %{
               no_of_runs: ^no_of_runs
             } = UsageTracking.generate_metrics(workflow, enabled, date)
    end

    test "includes the number of finished steps", %{
      date: date,
      enabled: enabled,
      no_of_steps: no_of_steps,
      workflow: workflow
    } do
      assert %{
               no_of_steps: ^no_of_steps
             } = UsageTracking.generate_metrics(workflow, enabled, date)
    end

    test "includes the number of active jobs for the finished steps", %{
      date: date,
      enabled: enabled,
      no_of_unique_jobs: no_of_unique_jobs,
      workflow: workflow
    } do
      assert %{
               no_of_active_jobs: ^no_of_unique_jobs
             } = UsageTracking.generate_metrics(workflow, enabled, date)
    end
  end

  describe "generate_metrics/3 (workflow) - cleartext enabled" do
    setup do
      generate_metrics_workflow_setup() |> Map.merge(%{enabled: true})
    end

    test "includes the hashed workflow uuid", %{
      date: date,
      enabled: enabled,
      hashed_uuid: hashed_uuid,
      workflow: workflow
    } do
      assert %{
               hashed_uuid: ^hashed_uuid
             } = UsageTracking.generate_metrics(workflow, enabled, date)
    end

    test "includes the cleartext uuid", %{
      date: date,
      enabled: enabled,
      workflow: workflow,
      workflow_uuid: workflow_uuid
    } do
      assert %{
               cleartext_uuid: ^workflow_uuid
             } = UsageTracking.generate_metrics(workflow, enabled, date)
    end

    test "includes the number of jobs", %{
      date: date,
      enabled: enabled,
      no_of_jobs: no_of_jobs,
      workflow: workflow
    } do
      assert %{
               no_of_jobs: ^no_of_jobs
             } = UsageTracking.generate_metrics(workflow, enabled, date)
    end

    test "includes the number of finished runs", %{
      date: date,
      enabled: enabled,
      no_of_runs: no_of_runs,
      workflow: workflow
    } do
      assert %{
               no_of_runs: ^no_of_runs
             } = UsageTracking.generate_metrics(workflow, enabled, date)
    end

    test "includes the number of finished steps", %{
      date: date,
      enabled: enabled,
      no_of_steps: no_of_steps,
      workflow: workflow
    } do
      assert %{
               no_of_steps: ^no_of_steps
             } = UsageTracking.generate_metrics(workflow, enabled, date)
    end

    test "includes the number of active jobs for the finished steps", %{
      date: date,
      enabled: enabled,
      no_of_unique_jobs: no_of_unique_jobs,
      workflow: workflow
    } do
      assert %{
               no_of_active_jobs: ^no_of_unique_jobs
             } = UsageTracking.generate_metrics(workflow, enabled, date)
    end
  end

  describe ".filter_eligible_workflows" do
    test "returns workflows that existed on or before the date" do
      date = ~D[2024-02-05]

      eligible_workflow_1 =
        insert(
          :workflow,
          name: "e-1",
          inserted_at: ~U[2024-02-04 12:00:00Z],
          deleted_at: nil
        )

      eligible_workflow_2 =
        insert(
          :workflow,
          name: "e-2",
          inserted_at: ~U[2024-02-05 23:59:59Z],
          deleted_at: nil
        )

      eligible_workflow_3 =
        insert(
          :workflow,
          name: "e-3",
          inserted_at: ~U[2024-02-04 12:00:00Z],
          deleted_at: ~U[2024-02-06 00:00:00Z]
        )

      eligible_workflow_4 =
        insert(
          :workflow,
          name: "e-4",
          inserted_at: ~U[2024-02-04 12:00:00Z],
          deleted_at: ~U[2024-02-06 00:00:01Z]
        )

      ineligible_workflow_deleted_before_1 =
        insert(
          :workflow,
          name: "ib-1",
          inserted_at: ~U[2024-02-04 12:00:00Z],
          deleted_at: ~U[2024-02-05 23:59:59Z]
        )

      ineligible_workflow_deleted_before_2 =
        insert(
          :workflow,
          name: "ib-2",
          inserted_at: ~U[2024-02-04 12:00:00Z],
          deleted_at: ~U[2024-02-05 23:59:58Z]
        )

      ineligible_workflow_created_after_1 =
        insert(
          :workflow,
          name: "ca-1",
          inserted_at: ~U[2024-02-06 00:00:00Z],
          deleted_at: nil
        )

      ineligible_workflow_created_after_2 =
        insert(
          :workflow,
          name: "ca-2",
          inserted_at: ~U[2024-02-06 00:00:01Z],
          deleted_at: ~U[2024-02-06 00:00:02Z]
        )

      all_workflows = [
        eligible_workflow_1,
        ineligible_workflow_deleted_before_1,
        ineligible_workflow_created_after_1,
        eligible_workflow_2,
        ineligible_workflow_deleted_before_2,
        eligible_workflow_3,
        ineligible_workflow_created_after_2,
        eligible_workflow_4
      ]

      expected_workflows = [
        eligible_workflow_1,
        eligible_workflow_2,
        eligible_workflow_3,
        eligible_workflow_4
      ]

      workflows =
        UsageTracking.find_eligible_workflows(all_workflows, date)

      assert workflows == expected_workflows
    end
  end

  describe ".finished_runs/2" do
    test "returns the subset of runs finished on the given date" do
      date = ~D[2024-02-05]
      finished_at = ~U[2024-02-05 12:11:10Z]
      other_finished_at = ~U[2024-02-04 12:11:10Z]

      finished_on_report_date = insert_finished_runs(finished_at)
      finished_on_other_date = insert_finished_runs(other_finished_at)
      unfinished = insert_unfinished_runs()

      run_list = finished_on_other_date ++ finished_on_report_date ++ unfinished

      assert UsageTracking.finished_runs(run_list, date) ==
               finished_on_report_date
    end

    defp insert_finished_runs(finished_at) do
      Run.final_states()
      |> Enum.map(fn state ->
        insert(
          :run,
          state: state,
          finished_at: finished_at,
          work_order: build(:workorder),
          dataclip: build(:dataclip),
          starting_job: build(:job)
        )
      end)
    end

    defp insert_unfinished_runs do
      [:available, :claimed, :started]
      |> Enum.map(fn state ->
        insert(
          :run,
          state: state,
          work_order: build(:workorder),
          dataclip: build(:dataclip),
          starting_job: build(:job)
        )
      end)
    end
  end

  describe ".finished_steps/2" do
    test "returns all run steps that finished on report date" do
      date = ~D[2024-02-05]
      finished_at = ~U[2024-02-05 12:11:10Z]
      other_finished_at = ~U[2024-02-04 12:11:10Z]

      run_1 =
        insert(
          :run,
          work_order: build(:workorder),
          dataclip: build(:dataclip),
          starting_job: build(:job)
        )

      run_2 =
        insert(
          :run,
          work_order: build(:workorder),
          dataclip: build(:dataclip),
          starting_job: build(:job)
        )

      finished_1 = insert_steps(run_1, finished_at, other_finished_at)
      finished_2 = insert_steps(run_2, finished_at, other_finished_at)

      run_1 = run_1 |> Repo.preload(:steps)
      run_2 = run_2 |> Repo.preload(:steps)

      runs = [run_1, run_2]
      expected_ids = for step <- finished_1 ++ finished_2, do: step.id

      actual_ids =
        for step <- UsageTracking.finished_steps(runs, date) do
          step.id
        end

      assert actual_ids == expected_ids
    end

    defp insert_steps(run, finished_at, other_finished_at) do
      insert_step = fn ->
        insert(
          :step,
          finished_at: finished_at,
          job: fn -> build(:job) end
        )
      end

      finished =
        insert_list(
          2,
          :run_step,
          run: run,
          step: insert_step
        )

      _finished_other =
        insert(
          :run_step,
          run: run,
          step:
            insert(
              :step,
              finished_at: other_finished_at,
              job: build(:job)
            )
        )

      _unfinished =
        insert(
          :run_step,
          run: run,
          step:
            insert(
              :step,
              finished_at: nil,
              job: build(:job)
            )
        )

      for run_step <- finished, do: run_step.step
    end
  end

  describe "unique_jobs/2" do
    test "returns unique jobs across all steps finished on report date" do
      date = ~D[2024-02-05]
      finished_at = ~U[2024-02-05 12:11:10Z]
      other_finished_at = ~U[2024-02-04 12:11:10Z]

      job_1 = insert(:job)
      job_2 = insert(:job)
      job_3 = insert(:job)
      job_4 = insert(:job)

      finished_on_date_1 = insert_step(job_1, finished_at)
      finished_on_date_2 = insert_step(job_2, finished_at)
      finished_on_date_3 = insert_step(job_1, finished_at)
      finished_on_another_date = insert_step(job_3, other_finished_at)
      unfinished = insert_step(job_4, nil)

      steps = [
        finished_on_date_1,
        finished_on_another_date,
        finished_on_date_3,
        finished_on_date_2,
        unfinished
      ]

      assert UsageTracking.unique_jobs(steps, date) == [job_1, job_2]
    end

    defp insert_step(job, finished_at) do
      insert(
        :run_step,
        run:
          build(
            :run,
            work_order: build(:workorder),
            starting_job: job,
            dataclip: build(:dataclip)
          ),
        step: build(:step, finished_at: finished_at, job: job)
      ).step
    end
  end

  describe "existing_users/1" do
    test "includes users created on or before the date" do
      eligible_user_1 =
        insert(
          :user,
          disabled: false,
          inserted_at: ~U[2024-02-05 23:59:59Z]
        )

      eligible_user_2 =
        insert(
          :user,
          disabled: true,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      ineligible_user_after_date =
        insert(
          :user,
          inserted_at: ~U[2024-02-06 00:00:01Z]
        )

      result = UsageTracking.existing_users(~D[2024-02-05]) |> Repo.all()

      assert result |> contains?(eligible_user_1)
      assert result |> contains?(eligible_user_2)
      refute result |> contains?(ineligible_user_after_date)
    end
  end

  describe "existing_users/2" do
    test "returns subset of user list inserted on or before the date" do
      eligible_user_1 =
        insert(:user, inserted_at: ~U[2024-02-05 23:59:59Z])

      eligible_user_2 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      eligible_user_3 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      ineligible_user_after_date =
        insert(:user, inserted_at: ~U[2024-02-06 00:00:01Z])

      user_list = [
        eligible_user_1,
        ineligible_user_after_date,
        eligible_user_3
      ]

      result =
        UsageTracking.existing_users(~D[2024-02-05], user_list)
        |> Repo.all()

      assert result |> contains?(eligible_user_1)
      assert result |> contains?(eligible_user_3)
      refute result |> contains?(eligible_user_2)
      refute result |> contains?(ineligible_user_after_date)
    end
  end

  describe "active_users/1" do
    test "returns users that have logged in in the last 30 days" do
      user_1 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _active_token =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2023-11-08 00:00:00Z],
          user: user_1
        )

      user_2 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _active_token =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2024-02-05 23:59:59Z],
          user: user_2
        )

      user_3 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _ineligible_token_older_than_30_days =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2023-11-07 23:59:59Z],
          user: user_3
        )

      user_4 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _ineligible_token_newer_than_report_date =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2024-02-06 00:00:01Z],
          user: user_4
        )

      user_5 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _ineligible_token_not_session =
        insert(
          :user_token,
          context: "api",
          inserted_at: ~U[2024-02-05 00:00:01Z],
          user: user_5
        )

      result = UsageTracking.active_users(~D[2024-02-05]) |> Repo.all()

      assert result |> contains?(user_1)
      assert result |> contains?(user_2)
      refute result |> contains?(user_3)
      refute result |> contains?(user_4)
      refute result |> contains?(user_5)
    end

    test "if user has more than one token, only includes user once" do
      user_1 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _active_token_user_1_1 =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2023-11-08 00:00:00Z],
          user: user_1
        )

      _active_token_user_1_2 =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2023-11-08 00:00:01Z],
          user: user_1
        )

      user_2 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _active_token_user_2_1 =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2024-02-05 23:59:59Z],
          user: user_2
        )

      result = UsageTracking.active_users(~D[2024-02-05]) |> Repo.all()

      assert result |> contains?(user_1)
      assert result |> contains?(user_2)
      assert length(result) == 2
    end
  end

  describe "active_users/2" do
    test "returns subset of user list that have logged in the last 90 days" do
      user_1 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _active_token_user_1 =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2023-11-08 00:00:00Z],
          user: user_1
        )

      user_2 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _active_token_user_2 =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2024-02-05 23:59:59Z],
          user: user_2
        )

      user_3 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _active_token_user_3 =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2023-11-08 00:00:00Z],
          user: user_3
        )

      user_4 =
        insert(:user, inserted_at: ~U[2024-02-04 01:00:00Z])

      _ineligible_token_older_than_90_days =
        insert(
          :user_token,
          context: "session",
          inserted_at: ~U[2023-11-07 23:59:59Z],
          user: user_4
        )

      user_list = [
        user_1,
        user_4,
        user_3
      ]

      result =
        UsageTracking.active_users(~D[2024-02-05], user_list) |> Repo.all()

      assert result |> contains?(user_1)
      assert result |> contains?(user_3)
      refute result |> contains?(user_2)
      refute result |> contains?(user_4)
    end
  end

  describe ".generate_report_data/3 - cleartext uuids disabled" do
    setup [:generate_report_data_setup, :setup_cleartext_uuids_disabled]

    test "sets the time that the report was generated at", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      %{generated_at: generated_at} =
        UsageTracking.generate_report_data(report_config, enabled, date)

      assert DateTime.diff(DateTime.utc_now(), generated_at, :second) < 1
    end

    test "contains hashed uuid of reporting instance", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      %{instance_id: instance_id} = report_config

      %{instance: %{hashed_uuid: hashed_uuid}} =
        UsageTracking.generate_report_data(report_config, enabled, date)

      assert hashed_uuid == build_hash(instance_id)
    end

    test "cleartext uuid of reporting instance is nil", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      assert %{
               instance: %{cleartext_uuid: nil}
             } = UsageTracking.generate_report_data(report_config, enabled, date)
    end

    test "indicates the version of lightning present on the instance", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      # Temporarily water-down the test to address constraints imposed by CI.
      %{instance: %{version: version}} =
        UsageTracking.generate_report_data(report_config, enabled, date)

      assert String.match?(version, ~r/\A\d+\.\d+\.\d+\z/)
    end

    test "includes the total number of users", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      _user_1 =
        insert(
          :user,
          inserted_at: ~U[2024-02-25 23:59:59Z]
        )

      _user_2 =
        insert(
          :user,
          inserted_at: ~U[2024-02-25 23:59:59Z]
        )

      _user_3 =
        insert(
          :user,
          inserted_at: ~U[2024-02-26 00:00:00Z]
        )

      assert %{
               instance: %{no_of_users: 2}
             } = UsageTracking.generate_report_data(report_config, enabled, date)
    end

    test "includes the total number of active users", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      within_threshold_date = Date.add(date, -89)

      {:ok, within_threshold_time, _offset} =
        DateTime.from_iso8601("#{within_threshold_date}T10:00:00Z")

      outside_threshold_date = Date.add(date, -90)

      {:ok, outside_threshold_time, _offset} =
        DateTime.from_iso8601("#{outside_threshold_date}T10:00:00Z")

      user_1 =
        insert(
          :user,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      _active_token =
        insert(
          :user_token,
          context: "session",
          inserted_at: within_threshold_time,
          user: user_1
        )

      user_2 =
        insert(
          :user,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      _inactive_token =
        insert(
          :user_token,
          context: "session",
          inserted_at: outside_threshold_time,
          user: user_2
        )

      assert %{
               instance: %{no_of_active_users: 1}
             } = UsageTracking.generate_report_data(report_config, enabled, date)
    end

    test "includes the operating system details", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      {_os_family, os_name_atom} = :os.type()

      os_name = os_name_atom |> Atom.to_string()

      assert String.match?(os_name, ~r/.{5,}/)

      assert %{instance: %{operating_system: ^os_name}} =
               UsageTracking.generate_report_data(report_config, enabled, date)
    end

    test "includes project details for projects created before date", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      after_date = Date.add(date, 1)

      project_1 = build_project(2, date)
      project_2 = build_project(5, after_date)
      project_3 = build_project(3, date)

      %{projects: projects} =
        UsageTracking.generate_report_data(report_config, enabled, date)

      projects
      |> assert_metrics(
        target: project_1,
        cleartext_enabled: enabled,
        date: date
      )

      projects
      |> assert_metrics(
        target: project_3,
        cleartext_enabled: enabled,
        date: date
      )

      projects |> refute_metrics(target: project_2)
    end

    test "indicates the version of the report data structure in use", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      assert %{version: "2"} =
               UsageTracking.generate_report_data(report_config, enabled, date)
    end

    test "indicates the applicable report date", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      assert %{report_date: ^date} =
               UsageTracking.generate_report_data(report_config, enabled, date)
    end
  end

  describe ".generate_report_data/3 - cleartext uuids enabled" do
    setup [:generate_report_data_setup, :setup_cleartext_uuids_enabled]

    test "sets the time that the report was generated at", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      %{generated_at: generated_at} =
        UsageTracking.generate_report_data(report_config, enabled, date)

      assert DateTime.diff(DateTime.utc_now(), generated_at, :second) < 1
    end

    test "contains hashed uuid of reporting instance", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      %{instance_id: instance_id} = report_config

      %{instance: %{hashed_uuid: hashed_uuid}} =
        UsageTracking.generate_report_data(report_config, enabled, date)

      assert hashed_uuid == build_hash(instance_id)
    end

    test "cleartext uuid of reporting instance is populated", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      %{instance_id: instance_id} = report_config

      assert %{
               instance: %{cleartext_uuid: ^instance_id}
             } = UsageTracking.generate_report_data(report_config, enabled, date)
    end

    test "indicates the version of lightning present on the instance", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      # Temporarily water-down the test to address constraints imposed by CI.
      %{instance: %{version: version}} =
        UsageTracking.generate_report_data(report_config, enabled, date)

      assert String.match?(version, ~r/\A\d+\.\d+\.\d+\z/)
    end

    test "includes the total number of users", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      _user_1 =
        insert(
          :user,
          inserted_at: ~U[2024-02-25 23:59:59Z]
        )

      _user_2 =
        insert(
          :user,
          inserted_at: ~U[2024-02-25 23:59:59Z]
        )

      _user_3 =
        insert(
          :user,
          inserted_at: ~U[2024-02-26 00:00:00Z]
        )

      assert %{
               instance: %{no_of_users: 2}
             } = UsageTracking.generate_report_data(report_config, enabled, date)
    end

    test "includes the total number of active users", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      within_threshold_date = Date.add(date, -89)

      {:ok, within_threshold_time, _offset} =
        DateTime.from_iso8601("#{within_threshold_date}T10:00:00Z")

      outside_threshold_date = Date.add(date, -90)

      {:ok, outside_threshold_time, _offset} =
        DateTime.from_iso8601("#{outside_threshold_date}T10:00:00Z")

      user_1 =
        insert(
          :user,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      _active_token =
        insert(
          :user_token,
          context: "session",
          inserted_at: within_threshold_time,
          user: user_1
        )

      user_2 =
        insert(
          :user,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      _inactive_token =
        insert(
          :user_token,
          context: "session",
          inserted_at: outside_threshold_time,
          user: user_2
        )

      assert %{
               instance: %{no_of_active_users: 1}
             } = UsageTracking.generate_report_data(report_config, enabled, date)
    end

    test "includes the operating system details", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      {_os_family, os_name_atom} = :os.type()

      os_name = os_name_atom |> Atom.to_string()

      assert String.match?(os_name, ~r/.{5,}/)

      assert %{instance: %{operating_system: ^os_name}} =
               UsageTracking.generate_report_data(report_config, enabled, date)
    end

    test "includes project details for projects created before date", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      after_date = Date.add(date, 1)

      project_1 = build_project(2, date)
      project_2 = build_project(5, after_date)
      project_3 = build_project(3, date)

      %{projects: projects} =
        UsageTracking.generate_report_data(report_config, enabled, date)

      projects
      |> assert_metrics(
        target: project_1,
        cleartext_enabled: enabled,
        date: date
      )

      projects
      |> assert_metrics(
        target: project_3,
        cleartext_enabled: enabled,
        date: date
      )

      projects |> refute_metrics(target: project_2)
    end

    test "indicates the version of the report data structure in use", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      assert %{version: "2"} =
               UsageTracking.generate_report_data(report_config, enabled, date)
    end

    test "indicates the applicable report date", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      assert %{report_date: ^date} =
               UsageTracking.generate_report_data(report_config, enabled, date)
    end
  end

  defp contains?(collection, desired_item) do
    collection |> Enum.find(fn item -> item.id == desired_item.id end)
  end

  defp find_instrumentation(instrumented_collection, identity) do
    hashed_uuid = build_hash(identity)

    instrumented_collection
    |> Enum.find(fn record -> record.hashed_uuid == hashed_uuid end)
  end

  defp build_hash(uuid), do: Base.encode16(:crypto.hash(:sha256, uuid))

  defp generate_metrics_project_setup do
    project_id = "3cfb674b-e878-470d-b7c0-cfa8f7e003ae"

    active_user_count = 2

    project =
      build_project(
        active_user_count,
        project_id,
        active_user_threshold_time: ~U[2023-11-08 00:00:00Z],
        report_time: ~U[2024-02-05 23:59:59Z]
      )

    eligible_workflow_1 =
      insert(:workflow, project: project, inserted_at: ~U[2024-02-05 23:59:59Z])
      |> Repo.preload([:runs, :jobs])

    eligible_workflow_2 =
      insert(:workflow, project: project, inserted_at: ~U[2024-02-05 23:59:59Z])
      |> Repo.preload([:runs, :jobs])

    ineligible_workflow =
      insert(:workflow, project: project, inserted_at: ~U[2024-02-06 00:00:00Z])
      |> Repo.preload([:runs, :jobs])

    other_project =
      build_project(
        3,
        Ecto.UUID.generate(),
        active_user_threshold_time: ~U[2023-11-08 00:00:00Z],
        report_time: ~U[2024-02-05 23:59:59Z]
      )

    _other_workflow =
      insert(:workflow,
        project: other_project,
        inserted_at: ~U[2024-02-05 23:59:59Z]
      )

    %{
      active_user_count: active_user_count,
      date: ~D[2024-02-05],
      eligible_workflow_1: eligible_workflow_1,
      eligible_workflow_2: eligible_workflow_2,
      hashed_id:
        "EECF8CFDD120E8DF8D9A12CA92AC3E815908223F95CFB11F19261A3C0EB34AEC",
      ineligible_workflow: ineligible_workflow,
      project:
        Repo.get(Project, project_id)
        |> Repo.preload([:users, workflows: [:runs, :jobs]]),
      project_id: project_id
    }
  end

  defp build_project(count, project_id, opts) do
    active_user_threshold_time = opts |> Keyword.get(:active_user_threshold_time)
    report_time = opts |> Keyword.get(:report_time)

    project =
      insert(
        :project,
        id: project_id,
        project_users:
          build_project_users(
            count,
            active_user_threshold_time,
            report_time
          )
      )

    project |> Repo.preload([:users, workflows: [:jobs, :runs]])
  end

  defp build_project_users(count, active_user_threshold_time, report_time) do
    active_users =
      build_list(
        count,
        :project_user,
        user: fn ->
          insert_active_user(active_user_threshold_time, report_time)
        end
      )

    user =
      build(
        :project_user,
        user: fn ->
          insert_user(active_user_threshold_time, report_time)
        end
      )

    day_after = report_time |> DateTime.add(1, :day)

    excluded_user =
      build(:project_user, user: build(:user, inserted_at: day_after))

    [excluded_user | [user | active_users]]
  end

  defp insert_active_user(active_user_threshold_time, report_time) do
    user = insert_user(active_user_threshold_time, report_time)

    insert(
      :user_token,
      context: "session",
      user: user,
      inserted_at: active_user_threshold_time
    )

    user
  end

  defp insert_user(active_user_threshold_time, report_time) do
    user = insert(:user, inserted_at: report_time)

    precedes_active_threshold =
      active_user_threshold_time
      |> DateTime.add(-1, :second)

    insert(
      :user_token,
      context: "session",
      user: user,
      inserted_at: precedes_active_threshold
    )

    user
  end

  defp generate_metrics_workflow_setup do
    date = ~D[2024-02-05]
    finished_at = ~U[2024-02-05 12:11:10Z]

    hashed_uuid =
      "EECF8CFDD120E8DF8D9A12CA92AC3E815908223F95CFB11F19261A3C0EB34AEC"

    workflow_uuid = "3cfb674b-e878-470d-b7c0-cfa8f7e003ae"

    no_of_jobs = 6
    no_of_work_orders = 3
    no_of_runs_per_work_order = 2
    no_of_unique_jobs_in_steps = 2
    no_of_steps_per_unique_job = 4

    workflow =
      build_workflow(
        workflow_uuid,
        no_of_jobs: no_of_jobs,
        no_of_work_orders: no_of_work_orders,
        no_of_runs_per_work_order: no_of_runs_per_work_order,
        no_of_unique_jobs_in_steps: no_of_unique_jobs_in_steps,
        no_of_steps_per_unique_job: no_of_steps_per_unique_job,
        finished_at: finished_at
      )

    _other_workflow =
      build_workflow(
        Ecto.UUID.generate(),
        no_of_jobs: no_of_jobs + 1,
        no_of_work_orders: no_of_work_orders + 1,
        no_of_runs_per_work_order: no_of_runs_per_work_order + 1,
        no_of_unique_jobs_in_steps: no_of_unique_jobs_in_steps + 1,
        no_of_steps_per_unique_job: no_of_steps_per_unique_job + 1,
        finished_at: finished_at
      )

    no_of_runs = no_of_work_orders * no_of_runs_per_work_order

    no_of_steps =
      no_of_runs * no_of_unique_jobs_in_steps * no_of_steps_per_unique_job

    %{
      date: date,
      finished_at: finished_at,
      hashed_uuid: hashed_uuid,
      no_of_jobs: no_of_jobs,
      no_of_runs: no_of_runs,
      no_of_steps: no_of_steps,
      no_of_unique_jobs: no_of_unique_jobs_in_steps,
      workflow: workflow,
      workflow_uuid: workflow_uuid
    }
  end

  defp build_workflow(workflow_id, opts) do
    no_of_jobs = opts |> Keyword.get(:no_of_jobs)
    no_of_work_orders = opts |> Keyword.get(:no_of_work_orders)
    no_of_runs_per_work_order = opts |> Keyword.get(:no_of_runs_per_work_order)
    no_of_unique_jobs_in_steps = opts |> Keyword.get(:no_of_unique_jobs_in_steps)
    no_of_steps_per_unique_job = opts |> Keyword.get(:no_of_steps_per_unique_job)
    finished_at = opts |> Keyword.get(:finished_at)

    workflow = insert(:workflow, id: workflow_id)

    jobs =
      no_of_jobs
      |> insert_list(:job, workflow: workflow)
      |> Enum.take(no_of_unique_jobs_in_steps)

    work_orders = insert_list(no_of_work_orders, :workorder, workflow: workflow)

    for work_order <- work_orders do
      insert_runs_with_steps(
        no_of_runs_per_work_order: no_of_runs_per_work_order,
        no_of_steps_per_unique_job: no_of_steps_per_unique_job,
        work_order: work_order,
        jobs: jobs,
        finished_at: finished_at
      )
    end

    workflow |> Repo.preload([:jobs, runs: [steps: [:job]]])
  end

  defp insert_runs_with_steps(opts) do
    no_of_runs_per_work_order = opts |> Keyword.get(:no_of_runs_per_work_order)
    no_of_steps_per_unique_job = opts |> Keyword.get(:no_of_steps_per_unique_job)
    work_order = opts |> Keyword.get(:work_order)
    jobs = opts |> Keyword.get(:jobs)
    finished_at = opts |> Keyword.get(:finished_at)

    [starting_job | _] = jobs

    insert_list(
      no_of_runs_per_work_order,
      :run,
      work_order: work_order,
      dataclip: &dataclip_builder/0,
      finished_at: finished_at,
      state: :success,
      starting_job: starting_job,
      steps: fn -> build_steps(jobs, no_of_steps_per_unique_job, finished_at) end
    )
  end

  defp build_steps(jobs, no_of_steps_per_unique_job, finished_at) do
    jobs
    |> Enum.flat_map(fn job ->
      build_list(
        no_of_steps_per_unique_job,
        :step,
        input_dataclip: &dataclip_builder/0,
        output_dataclip: &dataclip_builder/0,
        job: job,
        finished_at: finished_at
      )
    end)
  end

  defp dataclip_builder, do: build(:dataclip)

  defp generate_report_data_setup(context) do
    Map.merge(
      context,
      %{
        config: UsageTracking.enable_daily_report(DateTime.utc_now()),
        date: ~D[2024-02-25]
      }
    )
  end

  defp setup_cleartext_uuids_disabled(context) do
    Map.merge(context, %{cleartext_enabled: false})
  end

  defp setup_cleartext_uuids_enabled(context) do
    Map.merge(context, %{cleartext_enabled: true})
  end

  defp build_project(count, date) do
    {:ok, inserted_at, _offset} = DateTime.from_iso8601("#{date}T10:11:12Z")

    project =
      insert(
        :project,
        name: "proj-#{count}",
        inserted_at: inserted_at,
        project_users: build_project_users(count)
      )

    workflows = insert_list(1, :workflow, name: "wf-#{count}", project: project)

    for workflow <- workflows do
      [job | _] = insert_list(count, :job, workflow: workflow)
      work_orders = insert_list(count, :workorder, workflow: workflow)

      for work_order <- work_orders do
        insert_runs_with_steps_for_project(
          count: count,
          project: project,
          work_order: work_order,
          job: job,
          finished_at: inserted_at
        )
      end
    end

    project |> Repo.preload([:users, workflows: [:jobs, runs: [steps: [:job]]]])
  end

  defp build_project_users(count) do
    build_list(count, :project_user, user: fn -> build(:user) end)
  end

  defp insert_runs_with_steps_for_project(options) do
    count = Keyword.get(options, :count)
    project = Keyword.get(options, :project)
    work_order = Keyword.get(options, :work_order)
    job = Keyword.get(options, :job)
    finished_at = Keyword.get(options, :finished_at)

    dataclip_builder = fn -> build(:dataclip, project: project) end

    insert_list(
      count,
      :run,
      finished_at: finished_at,
      work_order: work_order,
      dataclip: dataclip_builder,
      starting_job: job,
      steps: fn ->
        build_list(
          count,
          :step,
          finished_at: finished_at,
          input_dataclip: dataclip_builder,
          output_dataclip: dataclip_builder,
          job: job
        )
      end
    )
  end

  defp assert_metrics(all_metrics, opts) do
    target = opts |> Keyword.get(:target)
    cleartext_enabled = opts |> Keyword.get(:cleartext_enabled)
    date = opts |> Keyword.get(:date)

    target_metrics = all_metrics |> find_instrumentation(target.id)

    expected_metrics =
      UsageTracking.generate_metrics(target, cleartext_enabled, date)

    assert target_metrics == expected_metrics
  end

  defp refute_metrics(all_metrics, opts) do
    target = opts |> Keyword.get(:target)

    refute all_metrics |> find_instrumentation(target.id)
  end
end
