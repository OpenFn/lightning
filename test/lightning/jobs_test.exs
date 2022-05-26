defmodule Lightning.JobsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Jobs
  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Repo

  describe "jobs" do
    alias Lightning.Jobs.Job

    import Lightning.JobsFixtures
    import Lightning.AccountsFixtures
    import Lightning.ProjectsFixtures

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
      job = job_fixture() |> unload_credential()

      assert Jobs.get_job!(job.id) == job

      assert_raise Ecto.NoResultsError, fn ->
        Jobs.get_job!(Ecto.UUID.generate())
      end
    end

    test "get_job/1 returns the job with given id" do
      job = job_fixture() |> unload_credential()

      assert Jobs.get_job(job.id) == job
      assert Jobs.get_job(Ecto.UUID.generate()) == nil
    end

    test "get_job_by_webhook/1 returns the job for a path" do
      job = job_fixture(trigger: %{}) |> unload_credential()

      assert Jobs.get_job_by_webhook(job.id) == job

      job = job_fixture(trigger: %{custom_path: "foo"}) |> unload_credential()
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
      {:ok, %Credential{} = credential} =
        Credentials.create_credential(%{
          body: %{},
          name: "My credential",
          user_id: user_fixture().id
        })

      assert {:ok, %Job{} = job} =
               Jobs.create_job(%{
                 body: "some body",
                 enabled: true,
                 name: "some name",
                 trigger: %{comment: "foo"},
                 adaptor: "@openfn/language-common",
                 credential_id: credential.id,
                 project_id: project_fixture().id
               })

      job = Repo.preload(job, :credential)

      assert job.credential_id == credential.id
      assert job.credential.name == credential.name
      assert job.credential.body == credential.body
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

  # Replace an preloaded Credential with an Ecto.Association.NotLoaded struct
  # Our factories product models with Credentials on them but our context
  # functions don't preload credentials - this helps make make our factories
  # uniform for these specific tests.
  defp unload_credential(job) do
    job
    |> Map.replace(:credential, %Ecto.Association.NotLoaded{
      __field__: :credential,
      __cardinality__: :one,
      __owner__: Lightning.Jobs.Job
    })
  end
end
