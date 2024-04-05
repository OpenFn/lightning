defmodule Lightning.UsageTracking.ResubmissionCandidatesWorkerTest do
  use Lightning.DataCase, async: false

  alias Lightning.UsageTracking.ResubmissionCandidatesWorker
  alias Lightning.UsageTracking.ResubmissionWorker

  @batch_size 5

  describe "perform/1 - impact tracker is reachable" do
    setup do
      now = DateTime.utc_now()

      failure_report_1 = now |> insert_report(:failure, -3)
      failure_report_2 = now |> insert_report(:failure, -2)
      failure_report_3 = now |> insert_report(:failure, -1)
      success_report = now |> insert_report(:success, -4)

      %{
        failure_report_1: failure_report_1,
        failure_report_2: failure_report_2,
        failure_report_3: failure_report_3,
        success_report: success_report
      }
    end

    test "indicates that the job completed successfully" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert perform_job(
          ResubmissionCandidatesWorker,
          %{batch_size: @batch_size}
        ) == :ok
      end)
    end

    test "enqueues jobs to resubmit reports", %{
      failure_report_1: failure_report_1,
      failure_report_2: failure_report_2,
      failure_report_3: failure_report_3,
      success_report: success_report
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        perform_job(ResubmissionCandidatesWorker, %{batch_size: @batch_size})
      end)

      assert_in_queue(failure_report_1)
      assert_in_queue(failure_report_2)
      assert_in_queue(failure_report_3)

      refute_in_queue(success_report)
    end
  end

  defp insert_report(now, status, time_offset) do
    today = now |> DateTime.to_date()

    insert(
      :usage_tracking_report,
      submission_status: status,
      inserted_at: now |> DateTime.add(time_offset, :second),
      report_date: today |> Date.add(time_offset)
    )
  end

  defp assert_in_queue(report) do
    assert_enqueued worker: ResubmissionWorker, args: %{id: report.id}
  end

  defp refute_in_queue(report) do
    refute_enqueued worker: ResubmissionWorker, args: %{id: report.id}
  end
end
