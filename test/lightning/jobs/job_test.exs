defmodule Lightning.Jobs.JobTest do
  alias Lightning.WorkflowsFixtures
  use Lightning.DataCase, async: true

  alias Lightning.Jobs.Job

  defp random_job_name(length) do
    for _ <- 1..length,
        into: "",
        do:
          <<Enum.random(
              ~c"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ "
            )>>
  end

  describe "changeset/2" do
    test "raises a constraint error when jobs in the same workflow have the same name" do
      workflow = WorkflowsFixtures.workflow_fixture()

      job_attrs = %{
        name: "Test Job",
        body: ~s[fn(state => state)],
        workflow_id: workflow.id
      }

      {:ok, _} =
        %Job{}
        |> Job.changeset(job_attrs)
        |> Repo.insert()

      {:error, changeset} =
        %Job{}
        |> Job.changeset(job_attrs)
        |> Repo.insert()

      refute changeset.valid?

      assert changeset.errors[:name] ==
               {"has already been taken",
                [
                  constraint: :unique,
                  constraint_name: "jobs_name_workflow_id_index"
                ]}
    end

    test "name can't be longer than 100 chars" do
      name = random_job_name(101)
      errors = Job.changeset(%Job{}, %{name: name}) |> errors_on()
      assert errors[:name] == ["should be at most 100 character(s)"]
    end

    test "name can't contain non url-safe chars" do
      ["My project @ OpenFn", "Can't have a / slash"]
      |> Enum.each(fn name ->
        errors = Job.changeset(%Job{}, %{name: name}) |> errors_on()
        assert errors[:name] == ["has invalid format"]
      end)
    end

    test "must have an adaptor" do
      errors = Job.changeset(%Job{}, %{adaptor: nil}) |> errors_on()
      assert errors[:adaptor] == ["can't be blank"]
    end
  end
end
