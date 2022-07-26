defmodule Lightning.JobsTest do
  use Oban.Testing, repo: Lightning.Repo
  use Lightning.DataCase, async: true

  alias Lightning.Jobs
  alias Lightning.Repo
  alias Lightning.Jobs.Job
  alias Lightning.Jobs.Scheduler

  import Lightning.JobsFixtures
  import Lightning.ProjectsFixtures
  import Lightning.CredentialsFixtures
  import Lightning.InvocationFixtures

  describe "jobs" do
    @invalid_attrs %{body: nil, enabled: nil, name: nil}

    test "list_jobs/0 returns all jobs" do
      job = job_fixture()
      assert Jobs.list_jobs() == [Jobs.get_job!(job.id)]
    end

    test "list_cron_jobs/0 returns all jobs" do
      job_fixture()
      job = job_fixture(trigger: %{type: :cron, cron_expression: "5 0 * 8 *"})
      assert Jobs.list_cron_jobs() == [Jobs.get_job!(job.id)]
    end

    test "find_cron_triggers/0 filter jobs on its cron trigger based off a given time" do
      job_fixture(trigger: %{type: :cron, cron_expression: "5 0 * 8 *"})

      job_1 = job_fixture(trigger: %{type: :cron, cron_expression: "* * * * *"})

      assert Jobs.find_cron_triggers(DateTime.utc_now() |> DateTime.to_unix()) ==
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
      job = job_fixture(trigger: %{}) |> unload_relation(:credential)

      assert Jobs.get_job_by_webhook(job.id) == job

      job =
        job_fixture(trigger: %{custom_path: "foo"})
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
        trigger: %{comment: "foo"},
        project_id: project_fixture().id
      }

      assert {:ok, %Job{} = job} = Jobs.create_job(valid_attrs)
      assert job.body == "some body"
      assert job.enabled == true
      assert job.name == "some name"

      assert job.trigger.comment == "foo"
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
                 trigger: %{comment: "foo"},
                 adaptor: "@openfn/language-common",
                 project_credential_id: project_credential.id,
                 project_id: project_fixture().id
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

  describe "get_workflow_for/1" do
    setup do
      project = project_fixture()

      w1_job =
        job_fixture(
          name: "webhook job",
          project_id: project.id,
          trigger: %{type: :webhook}
        )

      w1_on_fail_job =
        job_fixture(
          name: "on fail",
          project_id: project.id,
          trigger: %{type: :on_job_failure, upstream_job_id: w1_job.id}
        )

      w1_on_success_job =
        job_fixture(
          name: "on success",
          project_id: project.id,
          trigger: %{type: :on_job_success, upstream_job_id: w1_job.id}
        )

      w2_job =
        job_fixture(
          name: "other workflow",
          project_id: project.id,
          trigger: %{type: :webhook}
        )

      w2_on_fail_job =
        job_fixture(
          name: "on fail",
          project_id: project.id,
          trigger: %{type: :on_job_failure, upstream_job_id: w2_job.id}
        )

      unrelated_job =
        job_fixture(
          name: "unrelated job",
          trigger: %{type: :webhook}
        )

      %{
        project: project,
        w1_job: w1_job,
        w1_on_fail_job: w1_on_fail_job,
        w1_on_success_job: w1_on_success_job,
        w2_job: w2_job,
        w2_on_fail_job: w2_on_fail_job,
        unrelated_job: unrelated_job
      }
    end

    test "with a job", %{
      w1_job: w1_job,
      w1_on_fail_job: w1_on_fail_job,
      w1_on_success_job: w1_on_success_job
    } do
      assert Lightning.Jobs.get_workflow_for(w1_on_fail_job)
             |> MapSet.new()
             |> MapSet.subset?(
               [
                 w1_job,
                 w1_on_fail_job,
                 w1_on_success_job
               ]
               |> MapSet.new()
             )
    end

    test "with a project", %{
      project: project,
      w1_job: w1_job,
      w1_on_fail_job: w1_on_fail_job,
      w1_on_success_job: w1_on_success_job,
      w2_job: w2_job,
      w2_on_fail_job: w2_on_fail_job
    } do
      results = Lightning.Jobs.get_workflows_for(project) |> MapSet.new()

      assert results
             |> MapSet.subset?(
               [
                 {w1_job.id, w1_job},
                 {w1_job.id, w1_on_fail_job},
                 {w1_job.id, w1_on_success_job},
                 {w2_job.id, w2_job},
                 {w2_job.id, w2_on_fail_job}
               ]
               |> MapSet.new()
             )

      assert MapSet.size(results) == 5
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
