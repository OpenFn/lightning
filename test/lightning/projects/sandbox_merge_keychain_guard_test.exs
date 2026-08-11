defmodule Lightning.Projects.SandboxMergeKeychainGuardTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories
  import Lightning.SandboxMergeHelpers

  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Credentials.Scoping
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Projects.Sandboxes
  alias Lightning.Workflows.Workflow

  # Both the merge attach path and the provisioning clone path build the
  # keychain changeset on a base struct that already carries the destination
  # project, so the changeset's validate_default_credential_belongs_to_project
  # runs against that project. These tests pin that construction: the
  # validation must fire when the default credential is not shared with the
  # destination, and pass once it is.

  defp target_scoped_changeset(target, attrs) do
    %KeychainCredential{project: target, project_id: target.id}
    |> KeychainCredential.changeset(attrs)
  end

  describe "keychain changeset built for a target project" do
    test "rejects a default credential not shared with the target" do
      actor = insert(:user)
      target = insert(:project)
      other_project = insert(:project)

      credential = insert(:credential, user: actor)
      insert(:project_credential, project: other_project, credential: credential)

      changeset =
        target_scoped_changeset(target, %{
          name: "kc",
          path: "$.user_id",
          default_credential_id: credential.id
        })

      refute changeset.valid?

      assert errors_on(changeset)[:default_credential_id] == [
               "must belong to the same project"
             ]
    end

    test "accepts a default credential shared with the target" do
      actor = insert(:user)
      target = insert(:project)

      credential = insert(:credential, user: actor)
      insert(:project_credential, project: target, credential: credential)

      changeset =
        target_scoped_changeset(target, %{
          name: "kc",
          path: "$.user_id",
          default_credential_id: credential.id
        })

      assert changeset.valid?
    end
  end

  describe "keychain cloning during sandbox provisioning" do
    test "rejects a keychain whose default credential is not shared with the sandbox" do
      actor = insert(:user)

      parent =
        insert(:project, project_users: [%{user_id: actor.id, role: :owner}])

      credential = insert(:credential, user: actor)

      keychain =
        insert(:keychain_credential,
          project: parent,
          created_by: actor,
          default_credential: credential
        )

      workflow = insert(:workflow, project: parent)
      insert(:job, workflow: workflow, keychain_credential: keychain)

      error =
        assert_raise Ecto.InvalidChangesetError, fn ->
          Sandboxes.provision(parent, actor, %{name: "sb-unscoped-keychain"})
        end

      assert {"must belong to the same project", _} =
               error.changeset.errors[:default_credential_id]
    end

    test "clones a keychain whose default credential is shared with the parent" do
      actor = insert(:user)

      parent =
        insert(:project, project_users: [%{user_id: actor.id, role: :owner}])

      credential = insert(:credential, user: actor)
      insert(:project_credential, project: parent, credential: credential)

      keychain =
        insert(:keychain_credential,
          project: parent,
          created_by: actor,
          default_credential: credential
        )

      workflow = insert(:workflow, project: parent)
      insert(:job, workflow: workflow, keychain_credential: keychain)

      assert {:ok, sandbox} =
               Sandboxes.provision(parent, actor, %{name: "sb-shared-keychain"})

      assert %KeychainCredential{
               default_credential_id: default_credential_id,
               created_by_id: created_by_id
             } =
               Repo.get_by!(KeychainCredential,
                 project_id: sandbox.id,
                 name: keychain.name
               )

      assert default_credential_id == credential.id
      assert created_by_id == actor.id
    end
  end

  # Finding 4: the set of keychains attached to the target on merge is derived
  # from the same carried-source-workflow set the merge document is built from
  # (MergeProjects.carried_source_workflows/2). So a keychain used only by a
  # soft-deleted or unselected source workflow is never attached — matching what
  # the document actually carries — while live, included workflows attach exactly
  # as before.
  describe "merge/4 keychain attach scope" do
    test "does not attach a keychain used only by a soft-deleted source workflow" do
      {actor, parent} = parent_with_minimal_workflow!()
      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-kc"})

      sandbox_kc = insert_project_keychain!(sandbox, actor, "deleted-wf-kc")
      new_job = add_new_keychain_workflow!(sandbox, sandbox_kc, "DeletedFlow")

      soft_delete_workflow!(new_job.workflow_id)

      assert {:ok, _updated} = Sandboxes.merge(sandbox, parent, actor)

      refute Repo.exists?(
               from(k in KeychainCredential,
                 where: k.project_id == ^parent.id and k.name == "deleted-wf-kc"
               )
             )

      refute Repo.exists?(
               from(pc in ProjectCredential,
                 where:
                   pc.project_id == ^parent.id and
                     pc.credential_id == ^sandbox_kc.default_credential_id
               )
             )
    end

    test "attaches a keychain used by a live source workflow" do
      {actor, parent} = parent_with_minimal_workflow!()
      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-kc"})

      sandbox_kc = insert_project_keychain!(sandbox, actor, "live-wf-kc")
      new_job = add_new_keychain_workflow!(sandbox, sandbox_kc, "LiveFlow")

      assert {:ok, _updated} = Sandboxes.merge(sandbox, parent, actor)

      assert Repo.exists?(
               from(k in KeychainCredential,
                 where: k.project_id == ^parent.id and k.name == "live-wf-kc"
               )
             )

      assert Repo.exists?(
               from(pc in ProjectCredential,
                 where:
                   pc.project_id == ^parent.id and
                     pc.credential_id == ^sandbox_kc.default_credential_id
               )
             )

      merged_job = merged_job!(parent, "LiveFlow", new_job.name)
      assert keychain_scoping_violations(parent, merged_job) == []
    end

    test "a partial merge attaches only the selected workflows' keychains" do
      {actor, parent} = parent_with_minimal_workflow!()
      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-kc"})

      kc1 = insert_project_keychain!(sandbox, actor, "kc-1")
      kc2 = insert_project_keychain!(sandbox, actor, "kc-2")

      job1 = add_new_keychain_workflow!(sandbox, kc1, "Flow1")
      add_new_keychain_workflow!(sandbox, kc2, "Flow2")

      assert {:ok, _updated} =
               Sandboxes.merge(sandbox, parent, actor, %{
                 selected_workflow_ids: [job1.workflow_id]
               })

      assert Repo.exists?(
               from(k in KeychainCredential,
                 where: k.project_id == ^parent.id and k.name == "kc-1"
               )
             )

      assert Repo.exists?(
               from(pc in ProjectCredential,
                 where:
                   pc.project_id == ^parent.id and
                     pc.credential_id == ^kc1.default_credential_id
               )
             )

      refute Repo.exists?(
               from(k in KeychainCredential,
                 where: k.project_id == ^parent.id and k.name == "kc-2"
               )
             )

      refute Repo.exists?(
               from(pc in ProjectCredential,
                 where:
                   pc.project_id == ^parent.id and
                     pc.credential_id == ^kc2.default_credential_id
               )
             )
    end

    test "the merge stays scope-clean after excluding a soft-deleted workflow's keychain" do
      {actor, parent} = parent_with_minimal_workflow!()
      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-kc"})

      sandbox_kc = insert_project_keychain!(sandbox, actor, "deleted-wf-kc")
      new_job = add_new_keychain_workflow!(sandbox, sandbox_kc, "DeletedFlow")

      soft_delete_workflow!(new_job.workflow_id)

      assert {:ok, _updated} = Sandboxes.merge(sandbox, parent, actor)

      assert Scoping.out_of_project_references(
               parent.id,
               Scoping.job_refs_for_project(parent.id)
             ) == []
    end
  end

  defp soft_delete_workflow!(workflow_id) do
    Workflow
    |> Repo.get!(workflow_id)
    |> Ecto.Changeset.change(
      deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update!()
  end
end
