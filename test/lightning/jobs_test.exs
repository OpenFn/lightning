defmodule Lightning.JobsTest do
  alias Lightning.Attempt
  alias Lightning.Invocation.Dataclip
  use Lightning.DataCase, async: true

  alias Lightning.Jobs
  alias Lightning.Repo
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Scheduler
  alias Lightning.Workflows

  import Lightning.Factories

  describe "jobs" do
    @invalid_attrs %{body: nil, enabled: nil, name: nil}

    test "list_jobs/0 returns all jobs" do
      job = insert(:job)
      assert Jobs.list_jobs() == [Jobs.get_job!(job.id)]
    end

    test "list_active_cron_jobs/0 returns all active jobs with cron triggers" do
      insert(:job)

      workflow = insert(:workflow)

      t =
        insert(:trigger,
          workflow: workflow,
          type: :cron,
          cron_expression: "5 0 * 8 *"
        )

      enabled_job = insert(:job, workflow: workflow)

      insert(:edge,
        workflow: workflow,
        source_trigger_id: t.id,
        target_job_id: enabled_job.id
      )

      # disabled job
      insert(:edge,
        workflow: workflow,
        source_trigger_id: t.id,
        target_job: build(:job, workflow: workflow, enabled: false)
      )

      assert [active_job] = Jobs.list_active_cron_jobs()
      assert active_job.id == enabled_job.id
    end

    test "get_job!/1 returns the job with given id" do
      %{id: job_id} = insert(:job)

      assert %Job{id: ^job_id} = Jobs.get_job!(job_id)

      assert_raise Ecto.NoResultsError, fn ->
        Jobs.get_job!(Ecto.UUID.generate())
      end

      assert Jobs.get_job(Ecto.UUID.generate()) == nil
    end

    test "change_job/1 returns a job changeset" do
      job = insert(:job)
      assert %Ecto.Changeset{} = Jobs.change_job(job)
    end

    test "get_upstream_jobs_for/1 returns all jobs in same project except the job passed in" do
      workflow_1 = insert(:workflow)
      workflow_2 = insert(:workflow)

      workflow_1_job_1 =
        insert(:job, workflow: workflow_1)

      workflow_1_job_2 =
        insert(:job, workflow: workflow_1)

      workflow_2_job_1 =
        insert(:job, workflow: workflow_2)

      workflow_2_job_2 =
        insert(:job, workflow: workflow_2)

      assert Jobs.get_upstream_jobs_for(workflow_1_job_1) == [
               Jobs.get_job!(workflow_1_job_2.id)
             ]

      assert Jobs.get_upstream_jobs_for(workflow_2_job_1) == [
               Jobs.get_job!(workflow_2_job_2.id)
             ]
    end

    test "get_downstream_jobs_for/2 returns all jobs trigger by the provided one" do
      job = insert(:job)
      other_job = insert(:job, workflow: job.workflow)

      # connect other_job to job via an edge
      insert(:edge, %{
        source_job_id: job.id,
        workflow: job.workflow,
        target_job_id: other_job.id,
        condition: :on_job_failure
      })

      assert Jobs.get_downstream_jobs_for(job) == [
               Jobs.get_job!(other_job.id)
             ]

      assert Jobs.get_downstream_jobs_for(job, :on_job_failure) == [
               Jobs.get_job!(other_job.id)
             ]

      assert Jobs.get_downstream_jobs_for(job, :on_job_success) == []
      assert Jobs.get_downstream_jobs_for(other_job) == []
    end
  end

  describe "update_job/2" do
    test "changing a cron to a webhook trigger does NOT create a new workflow" do
      trigger = insert(:trigger, %{type: :cron, cron_expression: "* * * *"})

      workflow_id = trigger.workflow_id

      {:ok, %{workflow_id: ^workflow_id}} =
        Workflows.update_trigger(trigger, %{type: "webhook"})
    end

    test "update_job/2 with valid data updates the job" do
      job = insert(:job)

      update_attrs = %{
        body: "some updated body",
        enabled: false,
        name: "some updated name"
      }

      assert {:ok, %Job{} = job} = Jobs.update_job(job, update_attrs)
      assert job.body == "some updated body"
      assert job.enabled == false
      assert job.name == "some updated name"
    end

    test "update_job/2 with invalid data returns error changeset" do
      job = insert(:job)
      assert {:error, %Ecto.Changeset{}} = Jobs.update_job(job, @invalid_attrs)
    end

    test "delete_job/1 deletes the job" do
      job = insert(:job)
      assert {:ok, %Job{}} = Jobs.delete_job(job)
      assert_raise Ecto.NoResultsError, fn -> Jobs.get_job!(job.id) end
    end

    test "delete_job/1 can't delete job with downstream jobs" do
      job = insert(:job)

      {:ok, job1} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common",
          workflow_id: job.workflow_id
        })

      insert(:edge, %{
        condition: :on_job_success,
        source_job: job,
        target_job: job1,
        workflow: job.workflow
      })

      {:error, changeset} = Jobs.delete_job(job)

      assert %{workflow: ["This job is associated with downstream jobs"]} =
               errors_on(changeset)
    end
  end

  describe "create_job/1" do
    test "new job without a workflow" do
      assert_raise Postgrex.Error, fn ->
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common"
        })
      end
    end

    test "with a credential associated creates a Job with a credential" do
      project_credential =
        insert(:project_credential,
          credential:
            insert(:credential,
              name: "new credential",
              body: %{"foo" => "manchu"}
            )
        )

      assert {:ok, %Job{} = job} =
               Jobs.create_job(%{
                 body: "some body",
                 enabled: true,
                 name: "some name",
                 trigger: %{type: "webhook", comment: "foo"},
                 adaptor: "@openfn/language-common",
                 project_credential_id: project_credential.id,
                 workflow_id: insert(:workflow).id
               })

      job = Repo.preload(job, :credential)

      assert job.project_credential_id == project_credential.id
      assert job.credential.name == "new credential"
      assert job.credential.body == %{"foo" => "manchu"}
    end

    test "with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Jobs.create_job(@invalid_attrs)
    end

    test "with valid data creates a job" do
      valid_attrs = %{
        body: "some body",
        enabled: true,
        name: "some name",
        adaptor: "@openfn/language-common",
        workflow_id: insert(:workflow).id
      }

      assert {:ok, %Job{} = job} = Jobs.create_job(valid_attrs)
      assert job.body == "some body"
      assert job.enabled == true
      assert job.name == "some name"
    end

    test "with an upstream job returns a job with the upstream job's workflow_id" do
      workflow = insert(:workflow)

      {:ok, %Job{} = upstream_job} =
        Jobs.create_job(%{
          name: "job 1",
          body: "some body",
          enabled: true,
          adaptor: "@openfn/language-common",
          trigger: %{type: "webhook"},
          workflow_id: workflow.id
        })

      {:ok, %Job{} = job} =
        Jobs.create_job(%{
          name: "job 2",
          body: "some body",
          enabled: true,
          adaptor: "@openfn/language-common",
          trigger: %{type: "on_job_success", upstream_job_id: upstream_job.id},
          workflow_id: workflow.id
        })

      assert job.workflow_id == upstream_job.workflow_id
    end

    test "with an upstream job doesn't create a new workflow" do
      workflow = insert(:workflow)

      {:ok, %Job{} = upstream_job} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "job 1",
          adaptor: "@openfn/language-common",
          trigger: %{type: "webhook"},
          workflow_id: workflow.id
        })

      count_workflows_before = Workflows.list_workflows() |> Enum.count()

      {:ok, %Job{} = _job} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "job 2",
          adaptor: "@openfn/language-common",
          trigger: %{type: "on_job_success", upstream_job_id: upstream_job.id},
          workflow_id: workflow.id
        })

      assert count_workflows_before == Workflows.list_workflows() |> Enum.count()
    end
  end

  describe "Scheduler" do
    test "enqueue_cronjobs/1 enqueues a cron job that's never been run before" do
      job = insert(:job)

      trigger =
        insert(:trigger, %{
          type: :cron,
          cron_expression: "* * * * *",
          workflow: job.workflow
        })

      insert(:edge, %{
        workflow: job.workflow,
        source_trigger: trigger,
        target_job: job
      })

      Scheduler.enqueue_cronjobs()

      attempt = Repo.one(Lightning.Attempt)

      assert attempt.starting_trigger_id == trigger.id

      attempt = Repo.preload(attempt, [:dataclip])
      assert attempt.dataclip.type == :global
    end
  end

  describe "Scheduler repeats" do
    test "enqueue_cronjobs/1 enqueues a cron job that has been run before" do
      job =
        insert(:job,
          body: "fn(state => { console.log(state); return { changed: true }; })"
        )

      trigger =
        insert(:trigger, %{
          type: :cron,
          cron_expression: "* * * * *",
          workflow: job.workflow
        })

      insert(:edge, %{
        workflow: job.workflow,
        source_trigger: trigger,
        target_job: job
      })

      dataclip = insert(:dataclip)

      attempt =
        insert(:attempt,
          work_order:
            build(:workorder,
              workflow: job.workflow,
              dataclip: dataclip,
              trigger: trigger,
              state: :success
            ),
          starting_trigger: trigger,
          state: :success,
          dataclip: dataclip,
          runs: [
            build(:run,
              exit_code: 0,
              job: job,
              input_dataclip: dataclip,
              output_dataclip:
                build(:dataclip, type: :run_result, body: %{"changed" => true})
            )
          ]
        )

      [old_run] = attempt.runs

      _result = Scheduler.enqueue_cronjobs()

      new_attempt =
        Attempt
        |> last(:inserted_at)
        |> preload(dataclip: ^Dataclip.body_included_query())
        |> Repo.one()

      assert attempt.dataclip.type == :http_request
      assert old_run.input_dataclip.type == :http_request
      assert old_run.input_dataclip.body == %{}

      refute new_attempt.id == attempt.id
      assert new_attempt.dataclip.type == :run_result
      assert new_attempt.dataclip.body == old_run.output_dataclip.body
    end
  end
end
