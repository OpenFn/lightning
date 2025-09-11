defmodule Lightning.UsageTracking.ReportWorkerTest do
  use Lightning.DataCase, async: true

  import Lightning.Utils.Maps, only: [stringify_keys: 1]
  import Mock
  import Mox
  import Tesla.Mock

  alias Lightning.UsageTracking
  alias Lightning.UsageTracking.GithubClient
  alias Lightning.UsageTracking.Report
  alias Lightning.UsageTracking.ReportData
  alias Lightning.UsageTracking.ReportWorker

  @date ~D[2024-02-25]
  @host "https://foo.bar"

  describe "tracking is enabled - cleartext uuids are disabled" do
    setup_with_mocks([
      {GithubClient, [], [open_fn_commit?: fn _ -> true end]}
    ]) do
      cleartext_uuids_enabled = false

      report_config =
        UsageTracking.enable_daily_report(DateTime.utc_now())

      stub(Lightning.MockConfig, :usage_tracking_cleartext_uuids_enabled?, fn ->
        cleartext_uuids_enabled
      end)

      stub(Lightning.MockConfig, :usage_tracking_enabled?, fn -> true end)
      stub(Lightning.MockConfig, :usage_tracking_host, fn -> @host end)

      %{instance: instance_metrics} =
        ReportData.generate(report_config, cleartext_uuids_enabled, @date)

      # We can't match against all data as some of that contains dynamic
      # elements such as the time. The instance element provides us with
      # data to validate that the report was correctly configured

      %{
        expected_instance_metrics: stringify_keys(instance_metrics)
      }
    end

    test "persists a report instance", %{
      expected_instance_metrics: expected_metrics
    } do
      mock(fn _env -> %Tesla.Env{status: 200, body: %{status: "great"}} end)

      expected_date = @date

      perform_job(ReportWorker, %{date: @date})

      assert report = Report |> Repo.one!()

      assert %{
               data: %{"instance" => ^expected_metrics},
               report_date: ^expected_date
             } = report
    end

    test "submits the report data", %{
      expected_instance_metrics: expected_metrics
    } do
      mock(fn env ->
        if correct_host?(env, @host) && metrics_match?(env, expected_metrics) do
          %Tesla.Env{status: 200, body: %{status: "great"}}
        else
          flunk("Unrecognised call")
        end
      end)

      perform_job(ReportWorker, %{date: @date})
    end

    test "indicates that the job executed successfully" do
      mock(fn _env -> %Tesla.Env{status: 200, body: %{status: "great"}} end)

      assert perform_job(ReportWorker, %{date: @date}) == :ok
    end
  end

  describe "tracking is enabled - cleartext uuids are enabled" do
    setup_with_mocks([
      {GithubClient, [], [open_fn_commit?: fn _ -> true end]}
    ]) do
      cleartext_uuids_enabled = true

      report_config =
        UsageTracking.enable_daily_report(DateTime.utc_now())

      stub(Lightning.MockConfig, :usage_tracking_cleartext_uuids_enabled?, fn ->
        cleartext_uuids_enabled
      end)

      stub(Lightning.MockConfig, :usage_tracking_enabled?, fn -> true end)
      stub(Lightning.MockConfig, :usage_tracking_host, fn -> @host end)

      %{instance: instance_metrics} =
        ReportData.generate(report_config, cleartext_uuids_enabled, @date)

      # We can't match against all data as some of that contains dynamic
      # elements such as the time. The instance element provides us with
      # data to validate that the report was correctly configured

      %{
        expected_instance_metrics: stringify_keys(instance_metrics)
      }
    end

    test "persists a report instance", %{
      expected_instance_metrics: expected_metrics
    } do
      mock(fn _env -> %Tesla.Env{status: 200, body: %{status: "great"}} end)

      expected_date = @date

      perform_job(ReportWorker, %{date: @date})

      assert report = Report |> Repo.one!()

      assert %{
               data: %{"instance" => ^expected_metrics},
               report_date: ^expected_date
             } = report
    end

    test "submits the report data", %{
      expected_instance_metrics: expected_metrics
    } do
      mock(fn env ->
        if correct_host?(env, @host) && metrics_match?(env, expected_metrics) do
          %Tesla.Env{status: 200, body: %{status: "great"}}
        else
          flunk("Unrecognised call")
        end
      end)

      perform_job(ReportWorker, %{date: @date})
    end

    test "indicates that the job executed successfully" do
      mock(fn _env -> %Tesla.Env{status: 200, body: %{status: "great"}} end)

      assert perform_job(ReportWorker, %{date: @date}) == :ok
    end
  end

  describe "tracking is enabled - report for given date exists" do
    setup_with_mocks([
      {GithubClient, [], [open_fn_commit?: fn _ -> true end]}
    ]) do
      UsageTracking.enable_daily_report(DateTime.utc_now())

      stub(Lightning.MockConfig, :usage_tracking_cleartext_uuids_enabled?, fn ->
        false
      end)

      stub(Lightning.MockConfig, :usage_tracking_enabled?, fn -> true end)
      stub(Lightning.MockConfig, :usage_tracking_host, fn -> @host end)

      insert(:usage_tracking_report, report_date: @date, data: %{})

      :ok
    end

    test "does not submit the tracking data" do
      mock(fn _env -> flunk("Not expecting call to Impact Tracker") end)

      perform_job(ReportWorker, %{date: @date})
    end

    test "indicates that the job executed successfully" do
      mock(fn _env -> %Tesla.Env{status: 200, body: %{status: "great"}} end)

      assert perform_job(ReportWorker, %{date: @date}) == :ok
    end
  end

  describe "tracking is enabled - but no config" do
    setup do
      UsageTracking.disable_daily_report()

      stub(Lightning.MockConfig, :usage_tracking_cleartext_uuids_enabled?, fn ->
        false
      end)

      stub(Lightning.MockConfig, :usage_tracking_enabled?, fn -> true end)
      stub(Lightning.MockConfig, :usage_tracking_host, fn -> @host end)

      :ok
    end

    test "does not submit metrics to the ImpactTracker" do
      mock(fn _env -> flunk("Not expecting call to Impact Tracker") end)

      assert perform_job(ReportWorker, %{date: @date})
    end

    test "does not persist a report submission" do
      mock(fn _env -> %Tesla.Env{status: 200, body: %{status: "great"}} end)

      perform_job(ReportWorker, %{date: @date})

      refute Repo.one(Report)
    end

    test "indicates that the job executed successfully" do
      mock(fn _env -> %Tesla.Env{status: 200, body: %{status: "great"}} end)

      assert perform_job(ReportWorker, %{date: @date}) == :ok
    end
  end

  describe "tracking is disabled" do
    setup do
      UsageTracking.enable_daily_report(DateTime.utc_now())

      stub(Lightning.MockConfig, :usage_tracking_cleartext_uuids_enabled?, fn ->
        false
      end)

      stub(Lightning.MockConfig, :usage_tracking_enabled?, fn -> false end)
      stub(Lightning.MockConfig, :usage_tracking_host, fn -> @host end)

      :ok
    end

    test "does not submit metrics to the ImpactTracker" do
      mock(fn _env -> flunk("Not expecting call to Impact Tracker") end)

      assert perform_job(ReportWorker, %{date: @date})
    end

    test "does not persist a report submission" do
      mock(fn _env -> %Tesla.Env{status: 200, body: %{status: "great"}} end)

      perform_job(ReportWorker, %{date: @date})

      refute Repo.one(Report)
    end

    test "indicates that the job executed successfully" do
      mock(fn _env -> %Tesla.Env{status: 200, body: %{status: "great"}} end)

      assert perform_job(ReportWorker, %{date: @date}) == :ok
    end
  end

  defp metrics_match?(tesla_env, expected_instance_metrics) do
    submitted_instance_metrics = Jason.decode!(tesla_env.body)["instance"]

    submitted_instance_metrics == expected_instance_metrics
  end

  defp correct_host?(tesla_env, host) do
    String.contains?(tesla_env.url, host)
  end
end
