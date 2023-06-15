defmodule Lightning.WorkOrderServiceTest do
  use Lightning.DataCase, async: true

  alias Lightning.WorkOrderService

  import Lightning.{AccountsFixtures, JobsFixtures, InvocationFixtures}

  describe "multi_for_manual/3" do
    test "creates a manual workorder" do
      job = job_fixture()
      dataclip = dataclip_fixture()
      user = user_fixture()

      {:ok, %{attempt_run: attempt_run}} =
        WorkOrderService.multi_for_manual(job, dataclip, user)
        |> Repo.transaction()

      assert attempt_run.run.job_id == job.id
      assert attempt_run.run.input_dataclip_id == dataclip.id
      assert attempt_run.attempt.reason.dataclip_id == dataclip.id
      assert attempt_run.attempt.reason.user_id == user.id
      assert attempt_run.attempt.reason.type == :manual
    end
  end

  describe "create_webhook_workorder/2" do
    test "creates a webhook workorder" do
      %{job: job, trigger: trigger} = workflow_job_fixture()

      edge = Lightning.Workflows.get_edge_by_webhook(trigger.id)
      dataclip_body = %{"foo" => "bar"}

      Oban.Testing.with_testing_mode(:manual, fn ->
        WorkOrderService.subscribe(job.workflow.project_id)

        {:ok, %{attempt: attempt, attempt_run: attempt_run}} =
          WorkOrderService.create_webhook_workorder(edge, dataclip_body)

        assert_receive {Lightning.WorkOrderService,
                        %Lightning.Workorders.Events.AttemptCreated{}},
                       100

        assert_enqueued(
          worker: Lightning.Pipeline,
          args: %{attempt_run_id: attempt_run.id}
        )

        assert attempt_run.run.job_id == job.id

        assert attempt.reason.dataclip_id ==
                 attempt_run.run.input_dataclip_id

        assert attempt_run.attempt.reason.type == :webhook
      end)
    end
  end

  describe "retry_attempt_run/2" do
    setup do
      workflow_scenario()
    end

    test "creates a new attempt starting from an existing run", %{
      jobs: jobs,
      workflow: workflow
    } do
      work_order = work_order_fixture(workflow: workflow)

      dataclip = dataclip_fixture()
      user = user_fixture()

      # first attempt
      attempt_runs =
        Enum.map([jobs.a, jobs.b, jobs.c, jobs.e, jobs.f], fn j ->
          %{
            job_id: j.id,
            input_dataclip_id: dataclip.id,
            exit_code: 0
          }
        end) ++
          [%{job_id: jobs.d.id, exit_code: 1, input_dataclip_id: dataclip.id}]

      attempt =
        Lightning.Attempt.new(%{
          work_order_id: work_order.id,
          reason_id: work_order.reason_id,
          runs: attempt_runs
        })
        |> Repo.insert!()

      # find the failed run for this attempt
      attempt_run =
        from(ar in Lightning.AttemptRun,
          join: r in assoc(ar, :run),
          where: ar.attempt_id == ^attempt.id,
          where: r.exit_code == 1,
          preload: [run: [job: :workflow]]
        )
        |> Repo.one()

      Oban.Testing.with_testing_mode(:manual, fn ->
        WorkOrderService.subscribe(attempt_run.run.job.workflow.project_id)

        {:ok, %{attempt_run: attempt_run}} =
          WorkOrderService.retry_attempt_run(attempt_run, user)

        assert_receive {Lightning.WorkOrderService,
                        %Lightning.Workorders.Events.AttemptCreated{}},
                       100

        assert_enqueued(
          worker: Lightning.Pipeline,
          args: %{attempt_run_id: attempt_run.id}
        )
      end)
    end
  end
end
