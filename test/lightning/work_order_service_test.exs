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

        {:ok, %{attempt: attempt}} =
          WorkOrderService.create_webhook_workorder(edge, dataclip_body)

        assert_receive {Lightning.WorkOrderService,
                        %Lightning.Workorders.Events.AttemptCreated{}},
                       100

        attempt_run =
          Lightning.AttemptRun
          |> Repo.get_by!(attempt_id: attempt.id)
          |> Repo.preload([:run, [attempt: :reason]])

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

  describe "retry_attempt_runs/2" do
    test "creates a new attempt starting from an existing run" do
      scenario_a = workflow_scenario()
      scenario_b = workflow_scenario()
      work_order_a = work_order_fixture(workflow_id: scenario_a.workflow.id)
      work_order_b = work_order_fixture(workflow_id: scenario_b.workflow.id)
      dataclip_a = dataclip_fixture()
      dataclip_b = dataclip_fixture()
      user = user_fixture()

      # first attempt a
      attempt_a =
        Lightning.Attempt.new(%{
          work_order_id: work_order_a.id,
          reason_id: work_order_a.reason_id,
          runs:
            Enum.map([scenario_a.jobs.a, scenario_a.jobs.b], fn j ->
              %{
                job_id: j.id,
                input_dataclip_id: dataclip_a.id,
                exit_code: 0
              }
            end)
        })
        |> Repo.insert!()

      # first attempt b
      attempt_b =
        Lightning.Attempt.new(%{
          work_order_id: work_order_b.id,
          reason_id: work_order_b.reason_id,
          runs:
            Enum.map(
              [scenario_b.jobs.a, scenario_b.jobs.b, scenario_b.jobs.c],
              fn j ->
                %{
                  job_id: j.id,
                  input_dataclip_id: dataclip_b.id,
                  exit_code: 0
                }
              end
            )
        })
        |> Repo.insert!()

      # find the first runs for these two attemts
      run_a = hd(attempt_a.runs)
      run_b = hd(attempt_b.runs)

      attempt_runs =
        from(ar in Lightning.AttemptRun,
          join: r in assoc(ar, :run),
          where: ar.run_id in ^[run_a.id, run_b.id],
          preload: [run: [job: :workflow]]
        )
        |> Repo.all()

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _changes} = WorkOrderService.retry_attempt_runs(attempt_runs, user)

        all_runs_a =
          Repo.all(
            from(r in Lightning.Invocation.Run, where: r.job_id == ^run_a.job_id)
          )

        [new_run_a] = all_runs_a -- attempt_a.runs

        new_attempt_run_a =
          Repo.get_by(Lightning.AttemptRun, run_id: new_run_a.id)

        all_runs_b =
          Repo.all(
            from(r in Lightning.Invocation.Run, where: r.job_id == ^run_b.job_id)
          )

        [new_run_b] = all_runs_b -- attempt_b.runs

        new_attempt_run_b =
          Repo.get_by(Lightning.AttemptRun, run_id: new_run_b.id)

        assert_enqueued(
          worker: Lightning.Pipeline,
          args: %{attempt_run_id: new_attempt_run_a.id}
        )

        assert_enqueued(
          worker: Lightning.Pipeline,
          args: %{attempt_run_id: new_attempt_run_b.id}
        )
      end)
    end
  end
end
