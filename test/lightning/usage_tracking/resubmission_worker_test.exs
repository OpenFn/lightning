defmodule Lightning.UsageTracking.ResubmissionWorkerTest do
  use Lightning.DataCase, async: false

  import Mock
  import Lightning.ApplicationHelpers, only: [put_temporary_env: 3]

  alias Lightning.UsageTracking
  alias Lightning.UsageTracking.Report
  alias Lightning.UsageTracking.ResubmissionWorker

  setup do
    host = "https://unobtainium.test"

    report = insert(:usage_tracking_report, submission_status: :failure)

    put_temporary_env(:lightning, :usage_tracking, enabled: true, host: host)

    %{report: report, host: host}
  end

  describe "perform/1 - record exists - submission is successful" do
    setup_with_mocks(
      [
        {UsageTracking, [], [submit_report: fn _report, _host -> true end]}
      ],
      context
    ) do
      context
    end

    test "resubmits the report", %{host: host, report: report} do
      perform_job(ResubmissionWorker, %{id: report.id})

      assert_called(UsageTracking.submit_report(report, host))
    end

    test "returns :ok", %{report: report} do
      assert perform_job(ResubmissionWorker, %{id: report.id}) == :ok
    end
  end

  describe "perform/1 - record exists - resubmission is unsuccessful" do
    setup_with_mocks(
      [
        {UsageTracking, [], [submit_report: fn _report, _host -> false end]}
      ],
      context
    ) do
      context
    end

    test "resubmits the report", %{host: host, report: report} do
      perform_job(ResubmissionWorker, %{id: report.id})

      assert_called(UsageTracking.submit_report(report, host))
    end

    test "returns :ok", %{report: report} do
      assert perform_job(ResubmissionWorker, %{id: report.id}) == :ok
    end
  end

  describe "perform/1 - failed record can not be found" do
    setup_with_mocks(
      [
        {UsageTracking, [], [submit_report: fn _report, _host -> true end]}
      ],
      context
    ) do
      %{report: report} = context

      report
      |> Report.changeset(%{submission_status: :success})
      |> Repo.update()

      context
    end

    test "does not submit the report", %{report: report} do
      perform_job(ResubmissionWorker, %{id: report.id})

      assert_not_called(UsageTracking.submit_report(:_, :_))
    end

    test "returns :ok", %{report: report} do
      assert perform_job(ResubmissionWorker, %{id: report.id}) == :ok
    end
  end

  describe "perform/1 - usage tracking is not enabled" do
    setup_with_mocks(
      [
        {UsageTracking, [], [submit_report: fn _report, _host -> true end]}
      ],
      context
    ) do
      %{host: host} = context

      put_temporary_env(:lightning, :usage_tracking,
        enabled: false,
        host: host
      )

      context
    end

    test "does not submit the report", %{report: report} do
      perform_job(ResubmissionWorker, %{id: report.id})

      assert_not_called(UsageTracking.submit_report(:_, :_))
    end

    test "returns :ok", %{report: report} do
      assert perform_job(ResubmissionWorker, %{id: report.id}) == :ok
    end
  end
end
