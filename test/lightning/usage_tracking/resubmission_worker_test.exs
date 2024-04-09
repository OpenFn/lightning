defmodule Lightning.UsageTracking.ResubmissionWorkerTest do
  use Lightning.DataCase, async: false

  import Tesla.Mock
  import Lightning.ApplicationHelpers, only: [put_temporary_env: 3]

  alias Lightning.UsageTracking.Report
  alias Lightning.UsageTracking.ResubmissionWorker

  setup do
    host = "https://unobtainium.test"
    data = %{"test" => "metrics"}

    report =
      insert(
        :usage_tracking_report,
        data: data,
        submission_status: :failure
      )

    put_temporary_env(:lightning, :usage_tracking, enabled: true, host: host)

    %{host: host, data: data, report: report}
  end

  describe "perform/1" do
    test "submits the report to ImpactTracker", %{
      data: data,
      host: host,
      report: report
    } do
      mock(fn env ->
        if correct_host?(env, host) && data_match?(env, data) do
          %Tesla.Env{status: 200, body: %{status: "great"}}
        else
          flunk("Unrecognised call to Impact Tracker")
        end
      end)

      perform_job(ResubmissionWorker, %{id: report.id})
    end

    test "returns :ok", %{report: report} do
      mock(fn _env -> %Tesla.Env{status: 200, body: %{status: "great"}} end)

      assert perform_job(ResubmissionWorker, %{id: report.id}) == :ok
    end
  end

  describe "perform/1 - resubmission is unsuccessful" do
    test "returns :ok", %{report: report} do
      mock(fn _env -> %Tesla.Env{status: 500, body: %{status: "notgreat"}} end)

      assert perform_job(ResubmissionWorker, %{id: report.id}) == :ok
    end
  end

  describe "perform/1 - failed record can not be found" do
    setup context do
      %{report: report} = context

      report
      |> Report.changeset(%{submission_status: :success})
      |> Repo.update()

      context
    end

    test "does not submit the report", %{report: report} do
      mock(fn _env -> flunk("Not expecting call to Impact Tracker") end)

      perform_job(ResubmissionWorker, %{id: report.id})
    end

    test "returns :ok", %{report: report} do
      assert perform_job(ResubmissionWorker, %{id: report.id}) == :ok
    end
  end

  describe "perform/1 - usage tracking is not enabled" do
    setup context do
      %{host: host} = context

      put_temporary_env(:lightning, :usage_tracking,
        enabled: false,
        host: host
      )

      context
    end

    test "does not submit the report", %{report: report} do
      mock(fn _env -> flunk("Not expecting call to Impact Tracker") end)

      perform_job(ResubmissionWorker, %{id: report.id})
    end

    test "returns :ok", %{report: report} do
      assert perform_job(ResubmissionWorker, %{id: report.id}) == :ok
    end
  end

  defp data_match?(tesla_env, expected_data) do
    submitted_data = Jason.decode!(tesla_env.body)

    submitted_data == expected_data
  end

  defp correct_host?(tesla_env, host) do
    String.contains?(tesla_env.url, host)
  end
end
