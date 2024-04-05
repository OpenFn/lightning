demodule Lightning.UsageTracking.ResubmissionCandidatesWorkerTest do
  use Lightning.Data, async: false

  use Lightning.UsageTracking.ResubmissionCandidatesWorker
  use Lightning.UsageTracking.ResubmissionWorker

  @batch_size 5

  describe "perform/1 - impact tracker is reachable" do
    setup do
      now = DateTime.utc_now()

      failure_report_1 =
        insert(
          :usage_tracking_report,
          submission_status: :failure,
          inserted_at: DateTime.add(now, -3, :second)
        )

      failure_report_2 =
        insert(
          :usage_tracking_report,
          submission_status: :failure,
          inserted_at: DateTime.add(now, -2, :second)
        )

      failure_report_3 =
        insert(
          :usage_tracking_report,
          submission_status: :failure,
          inserted_at: DateTime.add(now, -1, :second)
        )

      success_report =
        insert(
          :usage_tracking_report,
          submission_status: :success,
          inserted_at: DateTime.add(now, -4, :second)
        )

      %{
        failure_report_1: failure_report_1,
        failure_report_2: failure_report_2,
        failure_report_3: failure_report_3,
        success_report: success_report
      }
    end

    test "enqueues jobs to resubmit reports", %{
      failure_report_1: failure_report_1,
      failure_report_2: failure_report_2,
      failure_report_3: failure_report_3,
      success_report: success_report
    } do
      Oban.Testing.with_test_mode(:manual, fn ->
        perform_job(ResubmissionCandidatesWorker, %{batch_size: @batch_size})
      end)

      assert_in_queue(failure_report_1)
      assert_in_queue(failure_report_2)
      assert_in_queue(failure_report_3)

      refute_in_queue(success_report)
    end
  end

  defp assert_in_queue(report) do
    assert_enqueued worker: ResubmissionWorker, args: %{id: report.id}
  end

  defp refute_in_queue(report) do
    refute_enqueued worker: ResubmissionWorker, args: %{id: report.id}
  end
end
