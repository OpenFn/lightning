defmodule Lightning.Workflows.QueryTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows.Query
  import Lightning.JobsFixtures
  import Lightning.AccountsFixtures
  import Lightning.ProjectsFixtures
  import Lightning.Factories

  test "jobs_for/1 with user" do
    user = user_fixture()
    project = project_fixture(project_users: [%{user_id: user.id}])

    job = job_fixture(project_id: project.id)
    _other_job = job_fixture()

    assert Query.jobs_for(user) |> Repo.all() == [
             job |> unload_relation(:trigger)
           ]
  end

  describe "enabled_cron_jobs_by_edge/0" do
    test "returns the jobs when trigger is enabled" do
      trigger =
        insert(:trigger, %{
          type: :cron,
          cron_expression: "* * * * *",
          enabled: true
        })

      job = insert(:job, workflow: trigger.workflow)

      insert(:edge, %{
        source_trigger: trigger,
        target_job: job,
        workflow: job.workflow,
        enabled: true
      })

      _disabled_cronjob =
        insert(:job, workflow: trigger.workflow)

      webhook_trigger = insert(:trigger, type: :webhook)

      _non_cron_job =
        insert(:job, workflow: webhook_trigger.workflow)

      jobs =
        Query.enabled_cron_jobs_by_edge()
        |> Repo.all()
        |> Enum.map(fn e -> e.target_job.id end)

      assert jobs == [job.id]
    end

    test "returns no jobs when trigger is disabled" do
      trigger =
        insert(:trigger, %{
          type: :cron,
          cron_expression: "* * * * *",
          enabled: false
        })

      job = insert(:job, workflow: trigger.workflow)

      insert(:edge, %{
        source_trigger: trigger,
        target_job: job,
        workflow: job.workflow,
        enabled: true
      })

      disabled_cronjob =
        insert(:job, workflow: trigger.workflow)

      insert(:edge, %{
        source_trigger: trigger,
        target_job: disabled_cronjob,
        workflow: disabled_cronjob.workflow,
        enabled: true
      })

      webhook_trigger = insert(:trigger, type: :webhook)

      non_cron_job =
        insert(:job, workflow: webhook_trigger.workflow)

      insert(:edge, %{
        source_trigger: webhook_trigger,
        target_job: non_cron_job,
        workflow: non_cron_job.workflow,
        enabled: true
      })

      jobs =
        Query.enabled_cron_jobs_by_edge()
        |> Repo.all()
        |> Enum.map(fn e -> e.target_job.id end)

      assert jobs == []
    end
  end

  describe "unused_snapshots/0" do
    test "identifies unused snapshots and respects references" do
      workflow = insert(:workflow)

      # Create an outdated unused snapshot
      old_unused_snapshot =
        insert(:snapshot, workflow: workflow, lock_version: 1)

      # Create snapshots that will be referenced by different entities
      old_referenced_by_workorder =
        insert(:snapshot, workflow: workflow, lock_version: 2)

      old_referenced_by_run =
        insert(:snapshot, workflow: workflow, lock_version: 3)

      old_referenced_by_step =
        insert(:snapshot, workflow: workflow, lock_version: 4)

      # Update workflow to new version, making all old snapshots outdated
      workflow
      |> Ecto.Changeset.change(%{lock_version: 5})
      |> Repo.update!()

      # Create current snapshot (should never be unused)
      current_snapshot =
        insert(:snapshot, workflow: workflow, lock_version: 5)

      # Before creating references, all old snapshots should be unused
      unused_ids = Query.unused_snapshots() |> Repo.all()
      assert old_unused_snapshot.id in unused_ids
      assert old_referenced_by_workorder.id in unused_ids
      assert old_referenced_by_run.id in unused_ids
      assert old_referenced_by_step.id in unused_ids
      refute current_snapshot.id in unused_ids
      assert length(unused_ids) == 4

      # Create references to some snapshots
      dataclip = insert(:dataclip, project: workflow.project)
      job = insert(:job, workflow: workflow)

      insert(:workorder,
        workflow: workflow,
        snapshot: old_referenced_by_workorder,
        dataclip: dataclip
      )

      work_order_for_run =
        insert(:workorder,
          workflow: workflow,
          snapshot: old_referenced_by_run,
          dataclip: dataclip
        )

      insert(:run,
        work_order: work_order_for_run,
        snapshot: old_referenced_by_run,
        dataclip: dataclip,
        starting_job: job
      )

      insert(:step, snapshot: old_referenced_by_step)

      # After creating references, only the truly unused snapshot should remain
      unused_ids = Query.unused_snapshots() |> Repo.all()
      assert unused_ids == [old_unused_snapshot.id]
      refute old_referenced_by_workorder.id in unused_ids
      refute old_referenced_by_run.id in unused_ids
      refute old_referenced_by_step.id in unused_ids
      refute current_snapshot.id in unused_ids
    end

    test "handles multiple workflows with unused snapshots" do
      workflow1 = insert(:workflow)
      workflow2 = insert(:workflow)

      # Create old snapshots
      old_snapshot1 =
        insert(:snapshot, workflow: workflow1, lock_version: 1)

      old_snapshot2 =
        insert(:snapshot, workflow: workflow2, lock_version: 1)

      # Update workflows to new versions
      workflow1
      |> Ecto.Changeset.change(%{lock_version: 2})
      |> Repo.update!()

      workflow2
      |> Ecto.Changeset.change(%{lock_version: 3})
      |> Repo.update!()

      # Create current snapshots
      current_snapshot1 =
        insert(:snapshot, workflow: workflow1, lock_version: 2)

      current_snapshot2 =
        insert(:snapshot, workflow: workflow2, lock_version: 3)

      unused_ids = Query.unused_snapshots() |> Repo.all()

      assert old_snapshot1.id in unused_ids
      assert old_snapshot2.id in unused_ids
      refute current_snapshot1.id in unused_ids
      refute current_snapshot2.id in unused_ids
      assert length(unused_ids) == 2
    end

    test "returns empty when all snapshots are current or referenced" do
      workflow = insert(:workflow, lock_version: 1)

      # Create current snapshot
      current_snapshot =
        insert(:snapshot, workflow: workflow, lock_version: 1)

      unused_ids = Query.unused_snapshots() |> Repo.all()

      refute current_snapshot.id in unused_ids
      assert unused_ids == []
    end
  end
end
