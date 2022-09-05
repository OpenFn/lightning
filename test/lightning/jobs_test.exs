defmodule Lightning.JobsTest do
  use Oban.Testing, repo: Lightning.Repo
  use Lightning.DataCase, async: true

  alias Lightning.Jobs
  alias Lightning.Repo
  alias Lightning.Jobs.Job
  alias Lightning.Jobs.Scheduler
  alias Lightning.Workflows

  import Lightning.JobsFixtures
  import Lightning.ProjectsFixtures
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

      assert Jobs.get_jobs_for_cron_execution(
               DateTime.utc_now()
               |> DateTime.to_unix()
             ) ==
               [Jobs.get_job!(job_1.id)]
    end

    test "get_job!/1 returns the job with given id" do
      job = job_fixture() |> unload_relation(:credential)

      assert Jobs.get_job!(job.id) == job

      assert_raise Ecto.NoResultsError, fn ->
        Jobs.get_job!(Ecto.UUID.generate())
      end
    end

    test "get_job/1 returns the job with given id" do
      job = job_fixture() |> unload_relation(:credential)

      assert Jobs.get_job(job.id) == job
      assert Jobs.get_job(Ecto.UUID.generate()) == nil
    end

    test "get_job_by_webhook/1 returns the job for a path" do
      job = job_fixture() |> unload_relation(:credential)

      assert Jobs.get_job_by_webhook(job.id) == job

      job =
        job_fixture(trigger: %{type: "webhook", custom_path: "foo"})
        |> unload_relation(:credential)

      assert Jobs.get_job_by_webhook(job.id) == nil
      assert Jobs.get_job_by_webhook("foo") == job
    end

    test "create_job/1 with valid data creates a job" do
      valid_attrs = %{
        body: "some body",
        enabled: true,
        name: "some name",
        adaptor: "@openfn/language-common",
        trigger: %{type: "webhook", comment: "foo"},
        project_id: project_fixture().id,
        workflow_id: workflow_fixture().id
      }

      assert {:ok, %Job{} = job} = Jobs.create_job(valid_attrs)
      assert job.body == "some body"
      assert job.enabled == true
      assert job.name == "some name"

      assert job.trigger.comment == "foo"
    end

    test "create_job/1 with a cron or webhook trigger creates a new workflow and returns a job with THAT workflow_id" do
      job_attrs = %{
        body: "some body",
        enabled: true,
        name: "some name",
        adaptor: "@openfn/language-common",
        trigger: %{type: "cron", cron_expression: "* * * *"},
        project_id: project_fixture().id
      }

      workflows_before = Workflows.list_workflows()
      count_workflows_before = Enum.count(workflows_before)

      {:ok, %Job{} = job_1} = Jobs.create_job(job_attrs)

      {:ok, %Job{} = job_2} =
        Jobs.create_job(%{job_attrs | trigger: %{type: "webhook"}})

      workflows_after = Workflows.list_workflows()
      count_workflows_after = Enum.count(workflows_after)

      assert count_workflows_before + 2 ==
               count_workflows_after

      assert Enum.member?(
               Enum.map(workflows_before, fn w -> w.id end),
               job_1.workflow_id
             )
             |> Kernel.not()

      assert Enum.member?(
               Enum.map(workflows_before, fn w -> w.id end),
               job_2.workflow_id
             )
             |> Kernel.not()

      assert Enum.member?(
               Enum.map(workflows_after, fn w -> w.id end),
               job_1.workflow_id
             )

      assert Enum.member?(
               Enum.map(workflows_after, fn w -> w.id end),
               job_2.workflow_id
             )
    end

    test "create_job/1 with an upstream job returns a job with the upstream job's workflow_id" do
      project_id = project_fixture().id

      {:ok, %Job{} = upstream_job} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common",
          trigger: %{type: "webhook"},
          project_id: project_id
        })

      {:ok, %Job{} = job} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common",
          trigger: %{type: "on_job_success", upstream_job_id: upstream_job.id},
          project_id: project_id
        })

      assert job.workflow_id == upstream_job.workflow_id
    end

    test "create_job/1 with an upstream job doesn't create a new workflow" do
      project_id = project_fixture().id

      {:ok, %Job{} = upstream_job} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common",
          trigger: %{type: "webhook"},
          project_id: project_id
        })

      count_workflows_before = Workflows.list_workflows() |> Enum.count()

      {:ok, %Job{} = _job} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common",
          trigger: %{type: "on_job_success", upstream_job_id: upstream_job.id},
          project_id: project_id
        })

      assert count_workflows_before == Workflows.list_workflows() |> Enum.count()
    end

    test "update_job/2 from a cron to a webhook trigger does NOT create a new workflow" do
      project_id = project_fixture().id

      {:ok, %Job{} = job} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common",
          trigger: %{type: "cron", cron_expression: "* * * *"},
          project_id: project_id
        })

      count_workflows_before = Workflows.list_workflows() |> Enum.count()

      Jobs.update_job(job, %{trigger: %{id: job.trigger.id, type: "webhook"}})

      assert count_workflows_before == Workflows.list_workflows() |> Enum.count()
    end

    test "update_job/2 from upstream_job A (in workflow 1) to upstream_job B (in workflow 2) changes the updated job's workflow_id to 2" do
      project_id = project_fixture().id

      {:ok, %Job{} = parent_job_1} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common",
          trigger: %{type: "cron"},
          project_id: project_id
        })

      {:ok, %Job{} = parent_job_2} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common",
          trigger: %{type: "cron"},
          project_id: project_id
        })

      {:ok, %Job{} = downstream_job_a} =
        Jobs.create_job(%{
          body: "some body",
          enabled: true,
          name: "some name",
          adaptor: "@openfn/language-common",
          trigger: %{type: "on_job_success", upstream_job_id: parent_job_1.id},
          project_id: project_id
        })

      assert downstream_job_a.workflow_id == parent_job_1.workflow_id

      {:ok, %Job{} = downstream_job_a} =
        Jobs.update_job(downstream_job_a, %{
          trigger: %{
            id: downstream_job_a.trigger.id,
            type: "on_job_success",
            upstream_job_id: parent_job_2.id
          }
        })

      assert downstream_job_a.workflow_id == parent_job_2.workflow_id
    end

    test "create_job/1 with a credential associated creates a Job with credential_id and a credential object" do
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
                 project_id: project_fixture().id,
                 workflow_id: workflow_fixture().id
               })

      job = Repo.preload(job, :credential)

      assert job.project_credential_id == project_credential.id
      assert job.credential.name == "new credential"
      assert job.credential.body == %{"foo" => "manchu"}
    end

    test "create_job/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Jobs.create_job(@invalid_attrs)
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

    test "change_job/1 returns a job changeset" do
      job = job_fixture()
      assert %Ecto.Changeset{} = Jobs.change_job(job)
    end

    test "get_upstream_jobs_for/1 returns all jobs except the job passed in" do
      job = job_fixture()
      other_job = job_fixture()
      assert Jobs.get_upstream_jobs_for(job) == [Jobs.get_job!(other_job.id)]
      assert Jobs.get_upstream_jobs_for(other_job) == [Jobs.get_job!(job.id)]
    end

    test "get_downstream_jobs_for/2 returns all jobs trigger by the provided one" do
      job = job_fixture()

      other_job =
        job_fixture(trigger: %{type: :on_job_failure, upstream_job_id: job.id})

      assert Jobs.get_downstream_jobs_for(job) == [Jobs.get_job!(other_job.id)]

      assert Jobs.get_downstream_jobs_for(job, :on_job_failure) == [
               Jobs.get_job!(other_job.id)
             ]

      assert Jobs.get_downstream_jobs_for(job, :on_job_success) == []
      assert Jobs.get_downstream_jobs_for(other_job) == []
    end
  end

  describe "Scheduler" do
    test "enqueue_cronjobs/1 enqueues a cron job that's never been run before" do
      job = job_fixture(trigger: %{type: :cron, cron_expression: "* * * * *"})

      Scheduler.enqueue_cronjobs()

      %{event_id: event_id} = Repo.one(Lightning.Invocation.Run)
      %{job_id: job_id} = Repo.get(Lightning.Invocation.Event, event_id)

      assert job_id == job.id

      run =
        %Jobs.Job{id: job.id}
        |> Lightning.Invocation.Query.last_successful_run_for_job()
        |> Repo.one()
        |> Repo.preload(:source_dataclip)
        |> Repo.preload(:result_dataclip)

      assert run.source_dataclip.type == :global
      assert run.source_dataclip.body == %{}
    end

    test "enqueue_cronjobs/1 enqueues a cron job that has been run before" do
      job =
        job_fixture(
          body: "fn(state => { console.log(state); return { changed: true }; })",
          trigger: %{type: :cron, cron_expression: "* * * * *"}
        )

      event = event_fixture(job_id: job.id)
      _run = run_fixture(event_id: event.id)

      Lightning.Pipeline.process(event)

      old =
        %Jobs.Job{id: job.id}
        |> Lightning.Invocation.Query.last_successful_run_for_job()
        |> Repo.one()
        |> Repo.preload(:source_dataclip)
        |> Repo.preload(:result_dataclip)

      _result = Scheduler.enqueue_cronjobs()

      new =
        %Jobs.Job{id: job.id}
        |> Lightning.Invocation.Query.last_successful_run_for_job()
        |> Repo.one()
        |> Repo.preload(:source_dataclip)
        |> Repo.preload(:result_dataclip)

      assert old.source_dataclip.type == :http_request
      assert old.source_dataclip.body == %{}

      assert new.source_dataclip.type == :run_result
      assert new.source_dataclip.body == old.result_dataclip.body
      assert new.result_dataclip.body == %{"changed" => true}
    end
  end
end
