defmodule Lightning.JobsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Auditing.Audit
  alias Lightning.Jobs
  alias Lightning.Workflows.Job
  alias Lightning.Workflows

  describe "jobs" do
    @invalid_attrs %{body: nil, enabled: nil, name: nil}

    test "list_jobs/0 returns all jobs" do
      job = insert(:job)
      assert Jobs.list_jobs() == [Jobs.get_job!(job.id)]
    end

    test "list_active_cron_jobs/0 returns all jobs with active cron triggers" do
      insert(:job)

      workflow = insert(:workflow)

      enabled_trigger =
        insert(:trigger,
          workflow: workflow,
          type: :cron,
          enabled: true,
          cron_expression: "5 0 * 8 *"
        )

      job_1 = insert(:job, workflow: workflow)

      insert(:edge,
        workflow: workflow,
        source_trigger: enabled_trigger,
        target_job: job_1
      )

      # disabled trigger
      disabled_trigger =
        insert(:trigger,
          workflow: workflow,
          type: :cron,
          enabled: false,
          cron_expression: "5 0 * 8 *"
        )

      job_2 = insert(:job, workflow: workflow)

      insert(:edge,
        workflow: workflow,
        source_trigger: disabled_trigger,
        target_job: job_2
      )

      assert [active_job] = Jobs.list_active_cron_jobs()
      assert active_job.id == job_1.id
    end

    test "get_job!/1 returns the job with given id" do
      %{id: job_id} = insert(:job)

      assert %Job{id: ^job_id} = Jobs.get_job!(job_id)

      assert_raise Ecto.NoResultsError, fn ->
        Jobs.get_job!(Ecto.UUID.generate())
      end

      assert Jobs.get_job_with_credential(Ecto.UUID.generate()) == nil
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
        condition_type: :on_job_failure
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
        name: "some updated name"
      }

      assert {:ok, %Job{} = job} = Jobs.update_job(job, update_attrs)
      assert job.body == "some updated body"

      assert job.name == "some updated name"
    end

    test "update_job/2 with invalid data returns error changeset" do
      job = insert(:job)
      assert {:error, %Ecto.Changeset{}} = Jobs.update_job(job, @invalid_attrs)
    end
  end

  describe "create_job/2" do
    setup do
      %{actor: insert(:user)}
    end

    test "new job without a workflow", %{actor: actor} do
      assert_raise Postgrex.Error, fn ->
        Jobs.create_job(
          %{
            body: "some body",
            name: "some name",
            adaptor: "@openfn/language-common"
          },
          actor
        )
      end
    end

    test "with a credential associated creates a Job with a credential", %{
      actor: actor
    } do
      project_credential =
        insert(:project_credential,
          credential:
            insert(:credential,
              name: "new credential",
              body: %{"foo" => "manchu"}
            )
        )

      assert {:ok, %Job{} = job} =
               Jobs.create_job(
                 %{
                   body: "some body",
                   name: "some name",
                   trigger: %{type: "webhook", comment: "foo"},
                   adaptor: "@openfn/language-common",
                   project_credential_id: project_credential.id,
                   workflow_id: insert(:workflow).id
                 },
                 actor
               )

      job = Repo.preload(job, :credential)

      assert job.project_credential_id == project_credential.id
      assert job.credential.name == "new credential"
      assert job.credential.body == %{"foo" => "manchu"}
    end

    test "with invalid data returns error changeset", %{actor: actor} do
      assert {:error, %Ecto.Changeset{}} = Jobs.create_job(@invalid_attrs, actor)
    end

    test "with valid data creates a job", %{actor: actor} do
      workflow = insert(:simple_workflow)

      valid_attrs = %{
        body: "some body",
        name: "some name",
        adaptor: "@openfn/language-common",
        workflow_id: workflow.id
      }

      assert {:ok, %Job{} = job} = Jobs.create_job(valid_attrs, actor)
      assert job.body == "some body"
      assert job.name == "some name"

      updated_workflow = Ecto.assoc(job, :workflow) |> Repo.one!()

      assert updated_workflow.lock_version > workflow.lock_version

      snapshot = Workflows.Snapshot.get_current_for(workflow)

      snapshotted_job = snapshot.jobs |> Enum.find(&(&1.id == job.id))

      assert snapshotted_job.id == job.id
      assert snapshotted_job.name == job.name
      assert snapshotted_job.adaptor == job.adaptor
      assert snapshotted_job.body == job.body
    end

    test "links the actor to the audit event for the snapshot", %{
      actor: %{id: actor_id} = actor
    } do
      workflow = insert(:simple_workflow)

      valid_attrs = %{
        body: "some body",
        name: "some name",
        adaptor: "@openfn/language-common",
        workflow_id: workflow.id
      }

      Jobs.create_job(valid_attrs, actor)

      audit = Audit |> Repo.one!()

      assert %{event: "snapshot_created", actor_id: ^actor_id} = audit
    end

    test "with an upstream job returns a job with the upstream job's workflow_id",
         %{
           actor: actor
         } do
      workflow = insert(:workflow)

      {:ok, %Job{} = upstream_job} =
        Jobs.create_job(
          %{
            name: "job 1",
            body: "some body",
            adaptor: "@openfn/language-common",
            trigger: %{type: "webhook"},
            workflow_id: workflow.id
          },
          actor
        )

      {:ok, %Job{} = job} =
        Jobs.create_job(
          %{
            name: "job 2",
            body: "some body",
            adaptor: "@openfn/language-common",
            trigger: %{type: "on_job_success", upstream_job_id: upstream_job.id},
            workflow_id: workflow.id
          },
          actor
        )

      assert job.workflow_id == upstream_job.workflow_id
    end

    test "with an upstream job doesn't create a new workflow", %{actor: actor} do
      workflow = insert(:workflow)

      {:ok, %Job{} = upstream_job} =
        Jobs.create_job(
          %{
            body: "some body",
            name: "job 1",
            adaptor: "@openfn/language-common",
            trigger: %{type: "webhook"},
            workflow_id: workflow.id
          },
          actor
        )

      count_workflows_before = Workflows.list_workflows() |> Enum.count()

      {:ok, %Job{} = _job} =
        Jobs.create_job(
          %{
            body: "some body",
            name: "job 2",
            adaptor: "@openfn/language-common",
            trigger: %{type: "on_job_success", upstream_job_id: upstream_job.id},
            workflow_id: workflow.id
          },
          actor
        )

      assert count_workflows_before == Workflows.list_workflows() |> Enum.count()
    end
  end
end
