defmodule Lightning.JobsTest do
  use Lightning.DataCase

  alias Lightning.Jobs
  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Repo

  describe "jobs" do
    alias Lightning.Jobs.Job

    import Lightning.JobsFixtures

    @invalid_attrs %{body: nil, enabled: nil, name: nil}

    test "list_jobs/0 returns all jobs" do
      job = job_fixture()
      assert Jobs.list_jobs() == [job]
    end

    test "get_job!/1 returns the job with given id" do
      job = job_fixture()
      assert Jobs.get_job!(job.id) == job
    end

    test "get_job_by_webhook/1 returns the job for a path" do
      job = job_fixture(%{trigger: %{}})
      assert Jobs.get_job_by_webhook(job.id) == job

      job = job_fixture(%{trigger: %{custom_path: "foo"}})
      assert Jobs.get_job_by_webhook(job.id) == nil
      assert Jobs.get_job_by_webhook("foo") == job
    end

    test "create_job/1 with valid data creates a job" do
      valid_attrs = %{
        body: "some body",
        enabled: true,
        name: "some name",
        trigger: %{comment: "foo"}
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
          name: "My credential"
        })

      assert {:ok, %Job{} = job} =
               Jobs.create_job(%{
                 body: "some body",
                 enabled: true,
                 name: "some name",
                 trigger: %{comment: "foo"},
                 credential_id: credential.id
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
      update_attrs = %{body: "some updated body", enabled: false, name: "some updated name"}

      assert {:ok, %Job{} = job} = Jobs.update_job(job, update_attrs)
      assert job.body == "some updated body"
      assert job.enabled == false
      assert job.name == "some updated name"
    end

    test "update_job/2 with invalid data returns error changeset" do
      job = job_fixture()
      assert {:error, %Ecto.Changeset{}} = Jobs.update_job(job, @invalid_attrs)
      assert job == Jobs.get_job!(job.id)
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
  end
end
