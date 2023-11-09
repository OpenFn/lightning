defmodule Lightning.AttemptServiceTest do
  use Lightning.DataCase, async: true

  import Lightning.JobsFixtures
  import Lightning.InvocationFixtures
  alias Lightning.Attempt
  alias Lightning.AttemptService
  alias Lightning.Invocation.{Run}
  import Lightning.Factories

  describe "attempts" do
    @tag skip: "Replaced by Attempts.enqueue/1"
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

  @tag :skip
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

  @tag skip: "Replaced by WorkOrders.retry/3"
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
          reason: work_order.reason
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

  @tag skip: "Replaced by WorkOrders.retry_many/3"
  describe "rerun_many/2" do
    setup do
      workflow_scenario()
    end

    test "creates a new attempt starting from an existing run for each attempt run",
         %{
           jobs: jobs,
           workflow: workflow
         } do
      work_order = work_order_fixture(workflow_id: workflow.id)
      dataclip = dataclip_fixture()
      user = insert(:user)

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
      run =
        from(r in Run,
          join: a in assoc(r, :attempts),
          where: a.id == ^attempt.id,
          where: r.exit_code == 1
        )
        |> Repo.one()

      # find the failed attempt run
      attempt_run =
        Repo.get_by(Lightning.AttemptRun, run_id: run.id, attempt_id: attempt.id)

      reason =
        Lightning.InvocationReasons.build(:retry, %{user: user, run: run})
        |> Repo.insert!()

      {:ok, %{attempt_runs: {1, [new_attempt_run]}}} =
        AttemptService.retry_many([attempt_run], [reason])
        |> Repo.transaction()

      refute new_attempt_run.attempt_id == attempt.id

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
          where: a.id == ^new_attempt_run.attempt_id,
          select: r.id
        )
        |> Repo.all()
        |> MapSet.new()

      assert MapSet.intersection(original_runs, new_runs) |> MapSet.size() == 5
      refute MapSet.member?(original_runs, new_attempt_run.run_id)
      assert MapSet.member?(new_runs, new_attempt_run.run_id)
    end
  end

  describe "list_for_rerun_from_start/1" do
    setup do
      workflow_scenario()
    end

    @tag :skip
    test "only the first attempt (oldest) is listed for each work order, ordered
          by workorder creation date, oldest to newest",
         %{
           jobs: jobs,
           workflow: workflow
         } do
      work_order_1 = work_order_fixture(workflow_id: workflow.id)
      work_order_2 = work_order_fixture(workflow_id: workflow.id)
      dataclip = dataclip_fixture()

      now = Timex.now()

      [work_order_1, work_order_2]
      |> Enum.each(fn work_order ->
        runs =
          Enum.map(
            [
              {jobs.a, -100},
              {jobs.b, -80},
              {jobs.c, -70},
              {jobs.d, -50},
              {jobs.e, -30},
              {jobs.f, -20}
            ],
            fn {j, time} ->
              %{
                job_id: j.id,
                input_dataclip_id: dataclip.id,
                exit_code: 0,
                started_at: Timex.shift(now, microseconds: time),
                finished_at: Timex.shift(now, microseconds: time + 5)
              }
            end
          )

        Lightning.Attempt.new(%{
          work_order_id: work_order.id,
          reason_id: work_order.reason_id,
          runs: runs
        })
        |> Repo.insert!()
      end)

      [ar1, ar2] =
        AttemptService.list_for_rerun_from_start([
          work_order_1.id,
          work_order_2.id
        ])

      assert Enum.all?([ar1, ar2], fn ar -> ar.run.job_id == jobs.a.id end)

      assert [ar1, ar2]
             |> Enum.uniq_by(& &1.attempt_id)
             |> Enum.count() == 2

      assert [ar1, ar2]
             |> Enum.uniq_by(& &1.attempt.work_order_id)
             |> Enum.count() == 2

      assert work_order_1.inserted_at < work_order_2.inserted_at
      assert ar1.attempt.work_order_id == work_order_1.id
      assert ar2.attempt.work_order_id == work_order_2.id
    end
  end

  describe "list_for_rerun_from_job/2" do
    setup do
      workflow_scenario()
    end

    @tag :skip
    test "returns the AttemptRuns for the latest Attempt of each work order
          associated with the job, ordered by workorder creation date, oldest to
          newest",
         %{
           jobs: jobs,
           workflow: workflow
         } do
      work_order_1 = work_order_fixture(workflow_id: workflow.id)
      work_order_2 = work_order_fixture(workflow_id: workflow.id)

      dataclip = dataclip_fixture()

      # First Attempts with all Jobs
      [_attempt_1_work_order_1, attempt_1_work_order_2] =
        Enum.map([work_order_1, work_order_2], fn work_order ->
          runs =
            Enum.map(
              Map.values(jobs),
              fn j ->
                %{
                  job_id: j.id,
                  input_dataclip_id: dataclip.id,
                  exit_code: 0
                }
              end
            )

          Lightning.Attempt.new(%{
            work_order_id: work_order.id,
            reason_id: work_order.reason_id,
            runs: runs
          })
          |> Repo.insert!()
        end)

      # Second Attempt For Work Order 1
      # Job d is missing
      dataclip2 = dataclip_fixture()

      runs =
        Enum.map([jobs.a, jobs.b, jobs.c, jobs.e, jobs.f], fn j ->
          %{
            job_id: j.id,
            input_dataclip_id: dataclip2.id,
            exit_code: 0
          }
        end)

      attempt_2_work_order_1 =
        Attempt.new(%{
          work_order_id: work_order_1.id,
          reason_id: work_order_1.reason_id,
          runs: runs
        })
        |> Repo.insert!()

      # Only the attempt for work order2 will be listed
      assert [attempt_run] =
               AttemptService.list_for_rerun_from_job(
                 [
                   work_order_1.id,
                   work_order_2.id
                 ],
                 jobs.d.id
               )

      assert attempt_run.attempt_id == attempt_1_work_order_2.id

      ## create the missing attempt run
      attempt_run2 =
        Lightning.AttemptRun.new(%{
          attempt_id: attempt_2_work_order_1.id,
          run: %{
            job_id: jobs.d.id,
            input_dataclip_id: dataclip2.id,
            exit_code: 0
          }
        })
        |> Repo.insert!()

      [first_attempt_run_in_list, second_attempt_run_in_list] =
        AttemptService.list_for_rerun_from_job(
          [
            work_order_1.id,
            work_order_2.id
          ],
          jobs.d.id
        )

      assert work_order_1.inserted_at < work_order_2.inserted_at

      assert first_attempt_run_in_list.attempt.work_order_id == work_order_1.id
      assert second_attempt_run_in_list.attempt.work_order_id == work_order_2.id

      assert first_attempt_run_in_list.id == attempt_run2.id
      assert second_attempt_run_in_list.id == attempt_run.id
    end
  end
end
