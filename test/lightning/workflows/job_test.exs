defmodule Lightning.Workflows.JobTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows.Job
  alias Lightning.Repo

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
    test "a malformed id is a changeset error, not an Ecto.ChangeError on save" do
      # An unsubstituted import placeholder reaching :id (a :binary_id field)
      # passes cast/3 and would only raise when dumped on insert. validate_uuid
      # surfaces it as a changeset error instead.
      changeset =
        Job.changeset(%Job{}, %{
          id: "__ID_JOB_Envoyer-dans-DHIS2__",
          name: "Test Job",
          body: "fn(state => state)",
          adaptor: "@openfn/language-common@latest"
        })

      refute changeset.valid?
      assert changeset.errors[:id] == {"is not a valid UUID", []}
    end

    test "malformed FK ids are changeset errors, not Ecto.ChangeError on save" do
      # workflow_id + keychain_credential_id together (no project_credential_id
      # so validate_exclusive doesn't fire and override the UUID error).
      changeset =
        Job.changeset(%Job{}, %{
          name: "Test Job",
          body: "fn(state => state)",
          adaptor: "@openfn/language-common@latest",
          workflow_id: "__ID_JOB_Fetch__",
          keychain_credential_id: "__ID_CRED_Foo___"
        })

      refute changeset.valid?
      assert changeset.errors[:workflow_id] == {"is not a valid UUID", []}

      assert changeset.errors[:keychain_credential_id] ==
               {"is not a valid UUID", []}

      # project_credential_id in isolation (no keychain set).
      project_changeset =
        Job.changeset(%Job{}, %{
          name: "Test Job",
          body: "fn(state => state)",
          adaptor: "@openfn/language-common@latest",
          project_credential_id: "__ID_CRED_Foo___"
        })

      refute project_changeset.valid?

      assert project_changeset.errors[:project_credential_id] ==
               {"is not a valid UUID", []}
    end

    test "FKs left unset stay valid" do
      workflow = insert(:workflow)

      changeset =
        Job.changeset(%Job{}, %{
          name: "Test Job",
          body: "fn(state => state)",
          adaptor: "@openfn/language-common@latest",
          workflow_id: workflow.id
        })

      assert changeset.valid?
      refute changeset.errors[:project_credential_id]
      refute changeset.errors[:keychain_credential_id]
    end

    test "accepts keychain_credential_id in changeset" do
      workflow = insert(:workflow)

      keychain_credential =
        insert(:keychain_credential, project: workflow.project)

      changeset =
        Job.changeset(%Job{}, %{
          name: "Test Job",
          body: "test",
          adaptor: "@openfn/language-common@latest",
          keychain_credential_id: keychain_credential.id,
          workflow_id: workflow.id
        })

      assert changeset.valid?
      refute changeset.errors[:keychain_credential_id]
    end

    test "validates that only one credential type can be set" do
      workflow = insert(:workflow)
      project_credential = insert(:project_credential, project: workflow.project)

      keychain_credential =
        insert(:keychain_credential, project: workflow.project)

      changeset =
        Job.changeset(%Job{}, %{
          name: "Test Job",
          body: "test",
          adaptor: "@openfn/language-common@latest",
          project_credential_id: project_credential.id,
          keychain_credential_id: keychain_credential.id,
          workflow_id: workflow.id
        })

      refute changeset.valid?

      # The validate_exclusive function adds the error to the field that was changed
      assert changeset.errors[:project_credential_id] ==
               {"cannot be set when the other credential type is also set", []}
    end

    test "validates that keychain credential belongs to the same project as the job" do
      workflow = insert(:workflow)
      other_project = insert(:project)
      keychain_credential = insert(:keychain_credential, project: other_project)

      workflow_with_project = Repo.preload(workflow, :project)

      changeset =
        %Job{}
        |> Ecto.Changeset.change()
        |> Job.put_workflow(Ecto.Changeset.change(workflow_with_project))
        |> Job.changeset(%{
          name: "Test Job",
          body: "test",
          adaptor: "@openfn/language-common@latest",
          keychain_credential_id: keychain_credential.id,
          workflow_id: workflow.id
        })

      refute changeset.valid?

      assert changeset.errors[:keychain_credential_id] ==
               {"must belong to the same project as the job", []}
    end

    test "allows both credential fields to be null" do
      workflow = insert(:workflow)

      changeset =
        Job.changeset(%Job{}, %{
          name: "Test Job",
          body: "test",
          adaptor: "@openfn/language-common@latest",
          workflow_id: workflow.id
        })

      assert changeset.valid?
    end

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
                 {"job name has already been taken",
                  [
                    constraint: :unique,
                    constraint_name: "jobs_name_workflow_id_index"
                  ]}
      end)
    end

    test "database constraint prevents job with both credential types" do
      workflow = insert(:workflow)
      project_credential = insert(:project_credential, project: workflow.project)

      keychain_credential =
        insert(:keychain_credential, project: workflow.project)

      # This should fail at the database level due to the constraint
      assert_raise Ecto.ConstraintError, fn ->
        insert(:job,
          workflow: workflow,
          project_credential: project_credential,
          keychain_credential: keychain_credential
        )
      end
    end

    test "name can't be longer than 100 chars" do
      name = random_job_name(101)
      errors = Job.changeset(%Job{}, %{name: name}) |> errors_on()
      assert errors[:name] == ["job name should be at most 100 character(s)"]
    end

    test "name can't contain non url-safe chars" do
      ["My project @ OpenFn", "Can't have a / slash"]
      |> Enum.each(fn name ->
        errors = Job.changeset(%Job{}, %{name: name}) |> errors_on()
        assert errors[:name] == ["job name has invalid format"]
      end)
    end

    test "must have an adaptor" do
      errors = Job.changeset(%Job{}, %{adaptor: nil}) |> errors_on()
      assert errors[:adaptor] == ["job adaptor can't be blank"]
    end
  end
end
