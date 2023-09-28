defmodule Lightning.Workflows.JobTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows.Job

  import Lightning.Factories

  defp random_job_name(length) do
    for _ <- 1..length,
        into: "",
        do:
          <<Enum.random(
              ~c"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ "
            )>>
  end

  describe "changeset/2" do
    test "raises a constraint error when jobs in the same workflow have the same downcased and hyphenated name" do
      workflow = insert(:workflow)

      [first | rest] = [
        "Validate form type",
        "validate form type",
        "validate-form-type",
        "validate-FORM type"
      ]

      insert(:job, workflow: workflow, name: first)

      Enum.each(rest, fn name ->
        {:error, changeset} =
          Job.changeset(
            %Job{},
            params_with_assocs(:job, workflow: workflow, name: name)
          )
          |> Repo.insert()

        refute changeset.valid?

        assert changeset.errors[:name] ==
                 {"has already been taken",
                  [
                    constraint: :unique,
                    constraint_name: "jobs_name_workflow_id_index"
                  ]}
      end)
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
