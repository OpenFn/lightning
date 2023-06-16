defmodule Lightning.AttemptServiceTest do
  use Lightning.DataCase, async: true

  import Lightning.JobsFixtures
  import Lightning.InvocationFixtures
  alias Lightning.Attempt
  alias Lightning.AttemptService
  alias Lightning.Invocation.{Run}
  import Lightning.Factories

  describe "attempts" do
    test "create_attempt/3 returns a new Attempt, with a new Run" do
      %{job: job, trigger: trigger} = workflow_job_fixture()
      work_order = work_order_fixture(workflow_id: job.workflow_id)
      reason = reason_fixture(trigger_id: trigger.id)

      job_id = job.id
      work_order_id = work_order.id
      reason_id = reason.id
      data_clip_id = reason.dataclip_id

      assert {:ok,
              %Attempt{
                work_order_id: ^work_order_id,
                reason_id: ^reason_id,
                runs: [%Run{job_id: ^job_id, input_dataclip_id: ^data_clip_id}]
              }} =
               AttemptService.create_attempt(
                 work_order,
                 job,
                 reason
               )
    end
  end

  describe "append/2" do
    test "adds a run to an existing attempt" do
      %{job: job, trigger: trigger} = workflow_job_fixture()
      work_order = work_order_fixture(workflow_id: job.workflow_id)
      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: trigger.id,
          dataclip_id: dataclip.id
        )

      attempt =
        %Attempt{
          work_order_id: work_order.id,
          reason_id: reason.id
        }
        |> Repo.insert!()

      new_run =
        Run.changeset(%Run{}, %{
          project_id: job.workflow.project_id,
          job_id: job.id,
          input_dataclip_id: dataclip.id
        })

      {:ok, attempt_run} = AttemptService.append(attempt, new_run)

      assert Ecto.assoc(attempt_run.run, :attempts) |> Repo.all() == [attempt]
    end
  end

  describe "retry" do
    setup do
      workflow_scenario()
    end

    test "creates a new attempt starting from an existing run", %{
      jobs: jobs,
      workflow: workflow
    } do
      user = insert(:user)
      dataclip = insert(:dataclip)

      work_order =
        insert(:workorder,
          workflow: workflow,
          reason: build(:reason, user: user, type: :manual, dataclip: dataclip)
        )

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
        insert(:attempt,
          work_order: work_order,
          runs: attempt_runs,
          reason_id: work_order.reason_id
        )

      # find the failed run for this attempt
      run =
        from(r in Run,
          join: a in assoc(r, :attempts),
          where: a.id == ^attempt.id,
          where: r.exit_code == 1
        )
        |> Repo.one()

      reason = Lightning.InvocationReasons.build(:retry, %{user: user, run: run})

      {:ok, %{attempt_run: attempt_run}} =
        AttemptService.retry(attempt, run, reason)
        |> Repo.transaction()

      refute attempt_run.attempt_id == attempt.id

      original_runs =
        from(r in Run,
          join: a in assoc(r, :attempts),
          where: a.id == ^attempt.id,
          select: r.id
        )
        |> Repo.all()
        |> MapSet.new()

      new_runs =
        from(r in Run,
          join: a in assoc(r, :attempts),
          where: a.id == ^attempt_run.attempt_id,
          select: r.id
        )
        |> Repo.all()
        |> MapSet.new()

      assert MapSet.intersection(original_runs, new_runs) |> MapSet.size() == 5
      refute MapSet.member?(original_runs, attempt_run.run_id)
      assert MapSet.member?(new_runs, attempt_run.run_id)
    end
  end
end
