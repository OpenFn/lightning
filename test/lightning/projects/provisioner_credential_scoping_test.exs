defmodule Lightning.Projects.ProvisionerCredentialScopingTest do
  use Lightning.DataCase, async: true

  alias Lightning.Projects.Provisioner
  alias Lightning.Workflows.Job

  import Ecto.Query
  import Lightning.Factories

  setup do
    Mox.stub(
      Lightning.Extensions.MockUsageLimiter,
      :limit_action,
      fn _action, _context -> :ok end
    )

    %{project: insert(:project), user: insert(:user)}
  end

  describe "import_document/4 keychain credential scoping" do
    test "rejects a new workflow whose job references a cross-project keychain",
         %{project: %{id: project_id} = project, user: user} do
      other = insert(:project)
      kc = insert(:keychain_credential, project: other)

      %{body: body} =
        document_with_new_workflow(project_id, %{
          "keychain_credential_id" => kc.id
        })

      assert {:error, changeset} =
               Provisioner.import_document(project, user, body)

      assert %{workflows: [%{jobs: job_errors}]} = errors_on(changeset)

      msg =
        Enum.find_value(job_errors, fn
          %{keychain_credential_id: [m]} -> m
          _ -> nil
        end)

      assert msg =~ "must belong to the same project"

      # Rollback proof: no job carrying the foreign keychain was persisted.
      refute Repo.exists?(
               from(j in Job, where: j.keychain_credential_id == ^kc.id)
             )
    end

    test "rejects a new job on an existing workflow referencing a cross-project keychain",
         %{project: %{id: project_id} = project, user: user} do
      other = insert(:project)
      kc = insert(:keychain_credential, project: other)

      %{body: body, workflow_id: workflow_id} =
        document_with_new_workflow(project_id)

      # Persist the workflow first so the second import adds a *new* job to an
      # already-existing workflow — the sandbox-merge-shaped no-op.
      assert {:ok, _project} = Provisioner.import_document(project, user, body)

      new_job_id = Ecto.UUID.generate()

      tainted_body =
        add_job_to_workflow(body, workflow_id, %{
          "id" => new_job_id,
          "name" => "leaky-job",
          "adaptor" => "@openfn/language-common@latest",
          "body" => "console.log('hello world');",
          "keychain_credential_id" => kc.id
        })

      assert {:error, changeset} =
               Provisioner.import_document(project, user, tainted_body)

      assert %{workflows: [%{jobs: job_errors}]} = errors_on(changeset)

      msg =
        Enum.find_value(job_errors, fn
          %{keychain_credential_id: [m]} -> m
          _ -> nil
        end)

      assert msg =~ "must belong to the same project"

      refute Repo.exists?(from(j in Job, where: j.id == ^new_job_id))
    end

    test "accepts a job referencing a same-project keychain", %{
      project: %{id: project_id} = project,
      user: user
    } do
      kc = insert(:keychain_credential, project: project)

      %{body: body, first_job_id: first_job_id} =
        document_with_new_workflow(project_id, %{
          "keychain_credential_id" => kc.id
        })

      assert {:ok, _imported} = Provisioner.import_document(project, user, body)

      assert %Job{keychain_credential_id: keychain_credential_id} =
               Repo.get(Job, first_job_id)

      assert keychain_credential_id == kc.id
    end

    test "rejects updating an existing job to a cross-project keychain", %{
      project: %{id: project_id} = project,
      user: user
    } do
      other = insert(:project)
      kc = insert(:keychain_credential, project: other)

      %{body: body, workflow_id: workflow_id, first_job_id: first_job_id} =
        document_with_new_workflow(project_id)

      assert {:ok, _project} = Provisioner.import_document(project, user, body)

      tainted_body =
        update_job_in_workflow(body, workflow_id, first_job_id, %{
          "keychain_credential_id" => kc.id
        })

      assert {:error, changeset} =
               Provisioner.import_document(project, user, tainted_body)

      assert %{workflows: [%{jobs: job_errors}]} = errors_on(changeset)

      msg =
        Enum.find_value(job_errors, fn
          %{keychain_credential_id: [m]} -> m
          _ -> nil
        end)

      assert msg =~ "must belong to the same project"

      # The persisted job was not re-pointed at the foreign keychain.
      assert %Job{keychain_credential_id: nil} = Repo.get(Job, first_job_id)
    end

    test "rejects a soft-deleted workflow carrying a job repointed to a cross-project credential",
         %{project: %{id: project_id} = project, user: user} do
      other = insert(:project)
      pc = insert(:project_credential, project: other)

      %{body: body, workflow_id: workflow_id, first_job_id: first_job_id} =
        document_with_new_workflow(project_id)

      assert {:ok, _project} = Provisioner.import_document(project, user, body)

      # Same document soft-deletes the workflow AND repoints its job at a
      # cross-project credential. The soft-delete guard only sees `:delete` at
      # the workflow level (jobs are cast afterwards), so the tainted ref still
      # casts and persists — the scan must not skip it just because the
      # carrier workflow is now soft-deleted.
      tainted_body =
        body
        |> update_job_in_workflow(workflow_id, first_job_id, %{
          "project_credential_id" => pc.id
        })
        |> soft_delete_workflow(workflow_id)

      assert {:error, changeset} =
               Provisioner.import_document(project, user, tainted_body)

      assert %{workflows: [%{jobs: job_errors}]} = errors_on(changeset)

      msg =
        Enum.find_value(job_errors, fn
          %{project_credential_id: [m]} -> m
          _ -> nil
        end)

      assert msg =~ "isn't available in this project"

      # Rollback proof: the job kept no foreign credential and the carrier
      # workflow was not soft-deleted.
      assert %Job{project_credential_id: nil} = Repo.get(Job, first_job_id)
    end
  end

  describe "import_document/4 with pre-existing cross-project references" do
    test "fails with a base error naming a poisoned job the document never touches",
         %{project: %{id: project_id} = project, user: user} do
      other = insert(:project)
      pc = insert(:project_credential, project: other)

      %{body: body, workflow_id: workflow_id, first_job_id: first_job_id} =
        document_with_new_workflow(project_id)

      assert {:ok, _project} = Provisioner.import_document(project, user, body)

      # Legacy data predating the scoping guard: repoint the persisted job
      # directly, bypassing the import.
      Repo.get!(Job, first_job_id)
      |> Ecto.Changeset.change(project_credential_id: pc.id)
      |> Repo.update!()

      rename_only_body = %{
        "id" => project_id,
        "name" => "test-project",
        "workflows" => [%{"id" => workflow_id, "name" => "renamed"}]
      }

      assert {:error, changeset} =
               Provisioner.import_document(project, user, rename_only_body)

      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ ~s(job "first-job")
      assert msg =~ "project_credential_id"

      # Rolled back: the rename never landed.
      assert Repo.get!(Lightning.Workflows.Workflow, workflow_id).name ==
               "default"
    end

    test "fails a full-document re-import when a persisted job holds a cross-project credential",
         %{project: %{id: project_id} = project, user: user} do
      other = insert(:project)
      pc = insert(:project_credential, project: other)
      pc_id = pc.id

      %{body: body, first_job_id: first_job_id} =
        document_with_new_workflow(project_id)

      assert {:ok, _project} = Provisioner.import_document(project, user, body)

      # Legacy poison: repoint the persisted job past the import path.
      Repo.get!(Job, first_job_id)
      |> Ecto.Changeset.change(project_credential_id: pc.id)
      |> Repo.update!()

      # Re-import the SAME document, byte-identical (the document never carried a
      # credential ref, so cast leaves the poisoned column untouched).
      assert {:error, changeset} =
               Provisioner.import_document(project, user, body)

      # Byte-identical params produce no `jobs` change, so the poisoned job is an
      # unchanged association: the violation lands as a top-level base error, not
      # a nested field error.
      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ ~s(job "first-job")
      assert msg =~ "isn't available in this project"

      # Rollback: the poisoned column is unchanged and nothing new landed.
      assert %Job{project_credential_id: ^pc_id} = Repo.get(Job, first_job_id)
    end
  end

  defp document_with_new_workflow(project_id, first_job_overrides \\ %{}) do
    first_job_id = Ecto.UUID.generate()
    second_job_id = Ecto.UUID.generate()
    trigger_id = Ecto.UUID.generate()
    workflow_id = Ecto.UUID.generate()
    trigger_edge_id = Ecto.UUID.generate()
    job_edge_id = Ecto.UUID.generate()

    first_job =
      Map.merge(
        %{
          "id" => first_job_id,
          "name" => "first-job",
          "adaptor" => "@openfn/language-common@latest",
          "body" => "console.log('hello world');"
        },
        first_job_overrides
      )

    workflow = %{
      "id" => workflow_id,
      "name" => "default",
      "jobs" => [
        first_job,
        %{
          "id" => second_job_id,
          "name" => "second-job",
          "adaptor" => "@openfn/language-common@latest",
          "body" => "console.log('hello world');"
        }
      ],
      "triggers" => [%{"id" => trigger_id, "enabled" => true}],
      "edges" => [
        %{
          "id" => trigger_edge_id,
          "source_trigger_id" => trigger_id,
          "condition_label" => "Always",
          "condition_type" => "js_expression",
          "condition_expression" => "true"
        },
        %{
          "id" => job_edge_id,
          "source_job_id" => first_job_id,
          "condition_type" => "on_job_success",
          "target_job_id" => second_job_id
        }
      ]
    }

    %{
      body: %{
        "id" => project_id,
        "name" => "test-project",
        "workflows" => [workflow]
      },
      workflow_id: workflow_id,
      first_job_id: first_job_id,
      second_job_id: second_job_id
    }
  end

  defp add_job_to_workflow(body, workflow_id, job) do
    update_workflow(body, workflow_id, fn workflow ->
      Map.update!(workflow, "jobs", &[job | &1])
    end)
  end

  defp update_job_in_workflow(body, workflow_id, job_id, overrides) do
    update_workflow(body, workflow_id, fn workflow ->
      Map.update!(workflow, "jobs", fn jobs ->
        Enum.map(jobs, fn
          %{"id" => ^job_id} = job -> Map.merge(job, overrides)
          job -> job
        end)
      end)
    end)
  end

  defp soft_delete_workflow(body, workflow_id) do
    update_workflow(body, workflow_id, &Map.put(&1, "delete", true))
  end

  defp update_workflow(body, workflow_id, fun) do
    Map.update!(body, "workflows", fn workflows ->
      Enum.map(workflows, fn
        %{"id" => ^workflow_id} = workflow -> fun.(workflow)
        workflow -> workflow
      end)
    end)
  end
end
