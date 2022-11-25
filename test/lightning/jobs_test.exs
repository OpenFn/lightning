defmodule Lightning.JobsTest do
  use Oban.Testing, repo: Lightning.Repo
  use Lightning.DataCase, async: true

  alias Lightning.Jobs
  alias Lightning.Repo
  alias Lightning.Jobs.Job
  alias Lightning.Jobs.Scheduler
  alias Lightning.Workflows

  import Lightning.JobsFixtures
  import Lightning.CredentialsFixtures
  import Lightning.InvocationFixtures
  import Lightning.WorkflowsFixtures

  describe "jobs" do
    @invalid_attrs %{body: nil, enabled: nil, name: nil}

    test "list_jobs/0 returns all jobs" do
      job = job_fixture()
      assert Jobs.list_jobs() == [Jobs.get_job!(job.id)]
    end

    test "list_active_cron_jobs/0 returns all active jobs with cron triggers" do
      job_fixture()

      enabled_job =
        job_fixture(trigger: %{type: :cron, cron_expression: "5 0 * 8 *"})

      _disabled_job =
        job_fixture(
          trigger: %{type: :cron, cron_expression: "5 0 * 8 *"},
          enabled: false
        )

      assert Jobs.list_active_cron_jobs() == [Jobs.get_job!(enabled_job.id)]
    end

    test "get_jobs_for_cron_execution/0 returns jobs to run for a given time" do
      _job_0 = job_fixture(trigger: %{type: :cron, cron_expression: "5 0 * 8 *"})

      job_1 = job_fixture(trigger: %{type: :cron, cron_expression: "* * * * *"})

      _disabled_job =
        job_fixture(
          trigger: %{type: :cron, cron_expression: "* * * * *"},
          enabled: false
        )

      assert Jobs.get_jobs_for_cron_execution(DateTime.utc_now()) == [
               Jobs.get_job!(job_1.id)
             ]
    end

    test "get_job!/1 returns the job with given id" do
      job = job_fixture()

      assert Jobs.get_job!(job.id) |> unload_relation(:workflow) == job

      assert_raise Ecto.NoResultsError, fn ->
        Jobs.get_job!(Ecto.UUID.generate())
      end

      assert Jobs.get_job(job.id) |> unload_relation(:workflow) == job
      assert Jobs.get_job(Ecto.UUID.generate()) == nil
    end

    test "get_job_by_webhook/1 returns the job for a path" do
      job = job_fixture()

      assert Jobs.get_job_by_webhook(job.trigger.id)
             |> unload_relation(:workflow) == job

      job = job_fixture(trigger: %{type: "webhook", custom_path: "foo"})

      assert Jobs.get_job_by_webhook(job.trigger.id) == nil
      assert Jobs.get_job_by_webhook("foo") |> unload_relation(:workflow) == job
    end

    test "change_job/1 returns a job changeset" do
      job = job_fixture()
      assert %Ecto.Changeset{} = Jobs.change_job(job)
    end

    test "get_upstream_jobs_for/1 returns all jobs in same project except the job passed in" do
      workflow_1 = workflow_fixture()
      workflow_2 = workflow_fixture()

      workflow_1_job_1 = job_fixture(workflow_id: workflow_1.id)
      workflow_1_job_2 = job_fixture(workflow_id: workflow_1.id)

      workflow_2_job_1 = job_fixture(workflow_id: workflow_2.id)
      workflow_2_job_2 = job_fixture(workflow_id: workflow_2.id)

      assert Jobs.get_upstream_jobs_for(workflow_1_job_1) == [
               Jobs.get_job!(workflow_1_job_2.id)
             ]

      assert Jobs.get_upstream_jobs_for(workflow_2_job_1) == [
               Jobs.get_job!(workflow_2_job_2.id)
             ]
    end

    test "get_downstream_jobs_for/2 returns all jobs trigger by the provided one" do
      job = job_fixture()

      other_job =
        job_fixture(
          trigger: %{type: :on_job_failure, upstream_job_id: job.id},
          workflow_id: job.workflow_id
        )

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
      workflow_id = workflow_fixture().id

      {:ok, %Job{} = job} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common",
          trigger: %{type: "cron", cron_expression: "* * * *"},
          workflow_id: workflow_id
        })

      {:ok,
       %Job{
         workflow_id: ^workflow_id,
         trigger: %{workflow_id: ^workflow_id}
       }} =
        Jobs.update_job(job, %{
          trigger: %{id: job.trigger.id, type: "webhook"}
        })
    end

    test "update_job/2 from upstream_job A (in workflow 1) to upstream_job B (in workflow 2) changes the updated job's workflow_id to 2" do
      workflow = workflow_fixture()

      {:ok, %Job{} = upstream_job_1} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common",
          trigger: %{type: "cron"},
          workflow_id: workflow.id
        })

      {:ok, %Job{} = upstream_job_2} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common",
          trigger: %{type: "cron"},
          workflow_id: workflow.id
        })

      {:ok, %Job{} = downstream_job_a} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common",
          trigger: %{type: "on_job_success", upstream_job_id: upstream_job_1.id},
          workflow_id: workflow.id
        })

      assert downstream_job_a.workflow_id == upstream_job_1.workflow_id

      {:ok, %Job{} = downstream_job_a} =
        Jobs.update_job(downstream_job_a, %{
          trigger: %{
            id: downstream_job_a.trigger.id,
            type: "on_job_success",
            upstream_job_id: upstream_job_2.id
          }
        })

      assert downstream_job_a.workflow_id == upstream_job_2.workflow_id
    end

    # With some of the refactoring, we have lost the ability to automatically
    # determine (easily) if a new Workflow must be made.
    # We must determine how important this feature is, and deal with it via
    # a dedicated function - and not automagically.
    @tag :skip
    test """
    update_job/2 from upstream_job A (in workflow 1) to cron or webhook
    creates a new workflow and changes the updated job's workflow_id
    to THAT new workflow
    """ do
      workflow = workflow_fixture()

      {:ok, %Job{} = cron_job} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common",
          trigger: %{type: "cron", cron_expression: "* * * *"},
          workflow_id: workflow.id
        })

      {:ok, %Job{} = downstream_job} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common",
          trigger: %{type: "on_job_success", upstream_job_id: cron_job.id},
          workflow_id: workflow.id
        })

      assert downstream_job.workflow_id == cron_job.workflow_id

      workflows_before = Workflows.list_workflows()
      count_workflows_before = Enum.count(workflows_before)

      {:ok, %Job{} = downstream_job} =
        Jobs.update_job(downstream_job, %{
          trigger: %{
            id: downstream_job.trigger.id,
            type: "webhook"
          }
        })

      assert downstream_job.trigger.upstream_job_id == nil

      workflows_after = Workflows.list_workflows()
      count_workflows_after = Enum.count(workflows_after)

      refute downstream_job.workflow_id == cron_job.workflow_id
      assert count_workflows_after == count_workflows_before + 1

      assert Enum.member?(
               Enum.map(workflows_before, fn w -> w.id end),
               downstream_job.workflow_id
             )
             |> Kernel.not()

      assert Enum.member?(
               Enum.map(workflows_after, fn w -> w.id end),
               downstream_job.workflow_id
             )
    end

    test "update_job/2 with valid data updates the job" do
      job = job_fixture()

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
      job = job_fixture()
      assert {:error, %Ecto.Changeset{}} = Jobs.update_job(job, @invalid_attrs)
    end

    test "delete_job/1 deletes the job" do
      job = job_fixture()
      assert {:ok, %Job{}} = Jobs.delete_job(job)
      assert_raise Ecto.NoResultsError, fn -> Jobs.get_job!(job.id) end
    end

    test "delete_job/1 can't delete job with downstream jobs" do
      job = job_fixture()

      {:ok, %Job{} = _} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common",
          trigger: %{type: "on_job_success", upstream_job_id: job.id},
          workflow_id: job.workflow_id
        })

      {:error, changeset} = Jobs.delete_job(job)

      assert {:trigger_id,
              {"This job is associated with downstream jobs",
               [constraint: :foreign, constraint_name: "jobs_trigger_id_fkey"]}} in changeset.errors
    end
  end

  describe "create_job/1" do
    test "new job without a workflow" do
      assert {:error, changeset} =
               Jobs.create_job(%{
                 body: "some body",
                 enabled: true,
                 name: "some name",
                 trigger: %{type: "webhook", comment: "foo"},
                 adaptor: "@openfn/language-common"
               })

      refute changeset.valid?

      assert {:workflow_id, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "with a credential associated creates a Job with a credential" do
      project_credential =
        project_credential_fixture(
          name: "new credential",
          body: %{"foo" => "manchu"}
        )

      assert {:ok, %Job{} = job} =
               Jobs.create_job(%{
                 body: "some body",
                 enabled: true,
                 name: "some name",
                 trigger: %{type: "webhook", comment: "foo"},
                 adaptor: "@openfn/language-common",
                 project_credential_id: project_credential.id,
                 workflow_id: workflow_fixture().id
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
        trigger: %{type: "webhook", comment: "foo"},
        workflow_id: workflow_fixture().id
      }

      assert {:ok, %Job{} = job} = Jobs.create_job(valid_attrs)
      assert job.body == "some body"
      assert job.enabled == true
      assert job.name == "some name"

      assert job.trigger.comment == "foo"
    end

    test "with an upstream job returns a job with the upstream job's workflow_id" do
      workflow = workflow_fixture()

      {:ok, %Job{} = upstream_job} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common",
          trigger: %{type: "webhook"},
          workflow_id: workflow.id
        })

      {:ok, %Job{} = job} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common",
          trigger: %{type: "on_job_success", upstream_job_id: upstream_job.id},
          workflow_id: workflow.id
        })

      assert job.workflow_id == upstream_job.workflow_id
    end

    test "with an upstream job doesn't create a new workflow" do
      workflow = workflow_fixture()

      {:ok, %Job{} = upstream_job} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common",
          trigger: %{type: "webhook"},
          workflow_id: workflow.id
        })

      count_workflows_before = Workflows.list_workflows() |> Enum.count()

      {:ok, %Job{} = _job} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common",
          trigger: %{type: "on_job_success", upstream_job_id: upstream_job.id},
          workflow_id: workflow.id
        })

      assert count_workflows_before == Workflows.list_workflows() |> Enum.count()
    end
  end

  describe "Scheduler" do
    test "enqueue_cronjobs/1 enqueues a cron job that's never been run before" do
      job = job_fixture(trigger: %{type: :cron, cron_expression: "* * * * *"})

      Scheduler.enqueue_cronjobs()

      run = Repo.one(Lightning.Invocation.Run)

      assert run.job_id == job.id

      run =
        %Jobs.Job{id: job.id}
        |> Lightning.Invocation.Query.last_successful_run_for_job()
        |> Repo.one()
        |> Repo.preload(:input_dataclip)
        |> Repo.preload(:output_dataclip)

      assert run.input_dataclip.type == :global
      assert run.input_dataclip.body == %{}
    end

    test "enqueue_cronjobs/1 enqueues a cron job that has been run before" do
      job =
        job_fixture(
          body: "fn(state => { console.log(state); return { changed: true }; })",
          trigger: %{type: :cron, cron_expression: "* * * * *"}
        )

      {:ok, %{attempt_run: attempt_run}} =
        Lightning.WorkOrderService.multi_for(:cron, job, dataclip_fixture())
        |> Repo.transaction()

      Lightning.Pipeline.process(attempt_run)

      old =
        %Jobs.Job{id: job.id}
        |> Lightning.Invocation.Query.last_successful_run_for_job()
        |> Repo.one()
        |> Repo.preload(:input_dataclip)
        |> Repo.preload(:output_dataclip)

      _result = Scheduler.enqueue_cronjobs()

      new =
        %Jobs.Job{id: job.id}
        |> Lightning.Invocation.Query.last_successful_run_for_job()
        |> Repo.one()
        |> Repo.preload(:input_dataclip)
        |> Repo.preload(:output_dataclip)

      assert old.input_dataclip.type == :http_request
      assert old.input_dataclip.body == %{}

      assert new.input_dataclip.type == :run_result
      assert new.input_dataclip.body == old.output_dataclip.body
      assert new.output_dataclip.body == %{"changed" => true}
    end
  end
end
