defmodule Lightning.Projects.SandboxMergeKeychainTest do
  use Lightning.DataCase, async: true

  import Ecto.Query
  import Lightning.Factories
  import Lightning.SandboxMergeHelpers

  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Credentials.Scoping
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Projects.Sandboxes
  alias Lightning.Repo

  # Behavioural coverage for re-pointing keychain credentials on sandbox merge
  # (H-7, issue #44). Everything is driven through `Sandboxes.merge/4` rather
  # than the internal builder so the assertions describe observable behaviour:
  # a merged keychain-using job must reference a *parent-owned* keychain, never
  # the sandbox's. Shared DB builders live in `Lightning.SandboxMergeHelpers`.

  describe "merge/4 keychain remapping" do
    test "merges a new sandbox workflow's keychain job onto a parent-owned keychain" do
      %{actor: actor, parent: parent} = parent_with_keychain_job!()

      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-kc"})

      sandbox_kc =
        Repo.get_by!(KeychainCredential, project_id: sandbox.id, name: "kc-main")

      new_job = add_new_keychain_workflow!(sandbox, sandbox_kc, "NewFlow")

      assert {:ok, _updated} = Sandboxes.merge(sandbox, parent, actor)

      merged_job = merged_job!(parent, "NewFlow", new_job.name)

      merged_kc =
        Repo.get!(KeychainCredential, merged_job.keychain_credential_id)

      assert merged_kc.project_id == parent.id
      assert keychain_scoping_violations(parent, merged_job) == []
      refute merged_job.keychain_credential_id == sandbox_kc.id
    end

    test "matches the parent's existing keychain by name without duplicating it" do
      %{actor: actor, parent: parent, kc: parent_kc} =
        parent_with_keychain_job!()

      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-kc"})

      sandbox_kc =
        Repo.get_by!(KeychainCredential, project_id: sandbox.id, name: "kc-main")

      new_job = add_new_keychain_workflow!(sandbox, sandbox_kc, "NewFlow")

      assert {:ok, _updated} = Sandboxes.merge(sandbox, parent, actor)

      merged_job = merged_job!(parent, "NewFlow", new_job.name)

      assert merged_job.keychain_credential_id == parent_kc.id

      parent_kc_count =
        Repo.aggregate(
          from(k in KeychainCredential,
            where: k.project_id == ^parent.id and k.name == "kc-main"
          ),
          :count
        )

      assert parent_kc_count == 1
    end

    test "attaches a sandbox-only keychain (and its default credential) to the parent" do
      {actor, parent} = parent_with_minimal_workflow!()

      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-kc"})

      sandbox_kc = insert_project_keychain!(sandbox, actor, "sandbox-only-kc")

      new_job = add_new_keychain_workflow!(sandbox, sandbox_kc, "NewFlow")

      refute Repo.exists?(
               from(k in KeychainCredential,
                 where:
                   k.project_id == ^parent.id and k.name == "sandbox-only-kc"
               )
             )

      assert {:ok, _updated} = Sandboxes.merge(sandbox, parent, actor)

      merged_job = merged_job!(parent, "NewFlow", new_job.name)
      refute is_nil(merged_job.keychain_credential_id)

      merged_kc =
        Repo.get!(KeychainCredential, merged_job.keychain_credential_id)

      assert merged_kc.project_id == parent.id
      assert merged_kc.name == "sandbox-only-kc"
      assert keychain_scoping_violations(parent, merged_job) == []

      # The default-credential link survived and is itself parent-scoped: the
      # attached keychain still points at the sandbox's underlying credential,
      # and that credential is now available in the parent as a ProjectCredential.
      assert merged_kc.default_credential_id == sandbox_kc.default_credential_id

      assert Repo.exists?(
               from(pc in ProjectCredential,
                 where:
                   pc.project_id == ^parent.id and
                     pc.credential_id == ^sandbox_kc.default_credential_id
               )
             )
    end

    test "attaches only keychains used by selected workflows on a partial merge" do
      {actor, parent} = parent_with_minimal_workflow!()

      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-kc"})

      selected_kc = insert_project_keychain!(sandbox, actor, "selected-kc")
      excluded_kc = insert_project_keychain!(sandbox, actor, "excluded-kc")

      selected_job =
        add_new_keychain_workflow!(sandbox, selected_kc, "SelectedFlow")

      add_new_keychain_workflow!(sandbox, excluded_kc, "ExcludedFlow")

      assert {:ok, _updated} =
               Sandboxes.merge(sandbox, parent, actor, %{
                 selected_workflow_ids: [selected_job.workflow_id]
               })

      # The selected workflow's merged job resolves to a parent-owned keychain,
      # in-project, and named for the selected keychain (not the sandbox's id).
      merged_job = merged_job!(parent, "SelectedFlow", selected_job.name)

      merged_kc =
        Repo.get!(KeychainCredential, merged_job.keychain_credential_id)

      assert merged_kc.project_id == parent.id
      assert merged_kc.name == "selected-kc"
      assert keychain_scoping_violations(parent, merged_job) == []

      # The excluded workflow's keychain is never carried over, and nothing in
      # the parent ends up pointing at the excluded keychain's id.
      refute Repo.exists?(
               from(k in KeychainCredential,
                 where: k.project_id == ^parent.id and k.name == "excluded-kc"
               )
             )

      refute Enum.any?(
               Scoping.job_refs_for_project(parent.id),
               &(&1.keychain_credential_id == excluded_kc.id)
             )
    end

    test "regression: a job matched in both projects keeps the target's own keychain" do
      # An untouched matched job carries the sandbox's keychain clone; the
      # name-match remap must resolve it back to the parent's own keychain.
      %{actor: actor, parent: parent, kc: parent_kc, job: parent_job} =
        parent_with_keychain_job!()

      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-kc"})

      assert {:ok, _updated} = Sandboxes.merge(sandbox, parent, actor)

      reloaded = Repo.reload!(parent_job)

      assert reloaded.keychain_credential_id == parent_kc.id
      assert keychain_scoping_violations(parent, reloaded) == []
    end

    test "repoints a name-colliding sandbox keychain to the parent's keychain (name-match wins)" do
      # A sandbox keychain whose NAME collides with an unrelated parent keychain
      # (different path/default) resolves to the parent's keychain on merge.
      # Documents that name-match is the accepted correctness rule here — it is
      # not a leak, because the merged job ends up on a parent-owned keychain.
      {actor, parent} = parent_with_minimal_workflow!()

      # Parent-owned "collide", NOT used by any parent job, so provisioning does
      # not clone it into the sandbox and we can create a distinct sandbox one.
      parent_collide_kc =
        insert_project_keychain!(parent, actor, "collide", "$.parent_path")

      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-kc"})

      sandbox_collide_kc =
        insert_project_keychain!(sandbox, actor, "collide", "$.sandbox_path")

      new_job =
        add_new_keychain_workflow!(sandbox, sandbox_collide_kc, "NewFlow")

      assert {:ok, _updated} = Sandboxes.merge(sandbox, parent, actor)

      merged_job = merged_job!(parent, "NewFlow", new_job.name)

      assert merged_job.keychain_credential_id == parent_collide_kc.id
      refute merged_job.keychain_credential_id == sandbox_collide_kc.id
      assert keychain_scoping_violations(parent, merged_job) == []
    end

    test "leaves an unselected passthrough workflow's target keychain untouched" do
      # Regression gap A: on a partial merge, an unselected target workflow is
      # passed through verbatim. Its job uses a TARGET-owned keychain, and the
      # remap's identity default must not disturb it.
      %{actor: actor, parent: parent, kc: parent_kc, job: parent_job} =
        parent_with_keychain_job!()

      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-kc"})

      # A brand-new, selected sandbox workflow with its own sandbox-only keychain.
      selected_kc = insert_project_keychain!(sandbox, actor, "selected-kc")

      selected_job =
        add_new_keychain_workflow!(sandbox, selected_kc, "SelectedFlow")

      assert {:ok, _updated} =
               Sandboxes.merge(sandbox, parent, actor, %{
                 selected_workflow_ids: [selected_job.workflow_id]
               })

      # Parent's "Alpha" was not selected, so it passes through unchanged.
      reloaded = Repo.reload!(parent_job)

      assert reloaded.keychain_credential_id == parent_kc.id
      assert keychain_scoping_violations(parent, reloaded) == []
    end

    test "rolls back the merge when a sandbox job references an out-of-project keychain" do
      # The fail-open case #44 must ultimately close. A sandbox job references a
      # keychain owned by a THIRD project (neither sandbox nor parent). The
      # keychain remap's identity fallthrough leaves it, attach_sandbox_keychains
      # won't attach it (not sandbox-owned), and the import validator no-ops
      # (workflow_id is nil at cast_assoc time for a new workflow). So today the
      # merge succeeds and plants a cross-project keychain reference in the
      # parent. This test asserts the merge fails-CLOSED and rolls back.
      %{actor: actor, parent: parent} = parent_with_keychain_job!()

      {actor2, third_project} = new_actor_and_parent!()

      third_kc =
        insert(:keychain_credential,
          project: third_project,
          created_by: actor2,
          name: "third-kc",
          path: "$.tenant_id",
          default_credential: nil
        )

      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-kc"})

      # Plant the dirty reference: a sandbox job pointing at the third project's
      # keychain (bypasses Job.changeset via Ecto.Changeset.change/2).
      add_new_keychain_workflow!(sandbox, third_kc, "NewFlow")

      assert {:error, _reason} = Sandboxes.merge(sandbox, parent, actor)

      # And the transaction left nothing behind: no job in the parent references
      # the third project's keychain.
      assert Scoping.out_of_project_references(
               parent.id,
               Scoping.job_refs_for_project(parent.id)
             ) == []

      refute Enum.any?(
               Scoping.job_refs_for_project(parent.id),
               &(&1.keychain_credential_id == third_kc.id)
             )
    end
  end
end
