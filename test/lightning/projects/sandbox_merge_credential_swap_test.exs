defmodule Lightning.Projects.SandboxMergeCredentialSwapTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Credentials.Scoping
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Projects.Sandboxes
  alias Lightning.Repo
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Workflow

  # Behavioural coverage for credential edits on a *matched* job: the
  # credential the sandbox job carries at merge time must win, remapped onto
  # the parent's own records — never silently reverted to whatever the parent
  # job had before.

  defp new_actor_and_parent! do
    actor = insert(:user)
    parent = insert(:project, name: "parent")
    insert(:project_user, project: parent, user: actor, role: :owner)
    {actor, parent}
  end

  # Parent with workflow "Alpha" whose job "A1" carries either the keychain
  # (`:keychain`) or the project credential (`:project_credential`). Both a
  # project credential and a keychain exist in the parent either way.
  defp parent_with_job!(credential_kind) do
    {actor, parent} = new_actor_and_parent!()

    cred = insert(:credential, body: %{"token" => "secret"}, user: actor)
    pc = insert(:project_credential, project: parent, credential: cred)

    kc =
      insert(:keychain_credential,
        project: parent,
        created_by: actor,
        name: "kc-main",
        path: "$.org_id",
        default_credential: cred
      )

    workflow = insert(:workflow, project: parent, name: "Alpha")
    trigger = insert(:trigger, workflow: workflow, type: :webhook, enabled: true)

    job =
      insert(:job,
        workflow: workflow,
        name: "A1",
        adaptor: "@openfn/language-common@latest",
        keychain_credential: if(credential_kind == :keychain, do: kc),
        project_credential: if(credential_kind == :project_credential, do: pc)
      )

    insert(:edge,
      workflow: workflow,
      source_trigger_id: trigger.id,
      target_job_id: job.id,
      condition_type: :always,
      enabled: true
    )

    %{actor: actor, parent: parent, cred: cred, pc: pc, kc: kc, job: job}
  end

  defp insert_project_keychain!(project, actor, name, path \\ "$.user_id") do
    cred = insert(:credential, body: %{"token" => name}, user: actor)
    insert(:project_credential, project: project, credential: cred)

    insert(:keychain_credential,
      project: project,
      created_by: actor,
      name: name,
      path: path,
      default_credential: cred
    )
  end

  defp sandbox_job!(sandbox, wf_name, job_name) do
    wf = Repo.get_by!(Workflow, project_id: sandbox.id, name: wf_name)
    Repo.get_by!(Job, workflow_id: wf.id, name: job_name)
  end

  defp sandbox_project_credential!(sandbox, credential_id) do
    Repo.get_by!(ProjectCredential,
      project_id: sandbox.id,
      credential_id: credential_id
    )
  end

  defp update_job_credential!(job, attrs) do
    job |> Job.changeset(attrs) |> Repo.update!()
  end

  defp job_scoping_violations(project, job) do
    Scoping.out_of_project_references(project.id, [
      %{
        key: job.id,
        project_credential_id: job.project_credential_id,
        keychain_credential_id: job.keychain_credential_id
      }
    ])
  end

  describe "merge/4 credential edits on a matched job" do
    test "keychain replaced by a project credential survives the merge" do
      %{actor: actor, parent: parent, cred: cred, pc: parent_pc, job: parent_job} =
        parent_with_job!(:keychain)

      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-swap"})

      sandbox_pc = sandbox_project_credential!(sandbox, cred.id)

      sandbox_job!(sandbox, "Alpha", "A1")
      |> update_job_credential!(%{
        project_credential_id: sandbox_pc.id,
        keychain_credential_id: nil
      })

      assert {:ok, _updated} = Sandboxes.merge(sandbox, parent, actor)

      reloaded = Repo.reload!(parent_job)

      assert reloaded.project_credential_id == parent_pc.id
      assert is_nil(reloaded.keychain_credential_id)
      assert job_scoping_violations(parent, reloaded) == []
    end

    test "project credential replaced by a keychain survives the merge" do
      %{actor: actor, parent: parent, job: parent_job} =
        parent_with_job!(:project_credential)

      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-swap"})

      swap_kc = insert_project_keychain!(sandbox, actor, "swap-kc")

      sandbox_job!(sandbox, "Alpha", "A1")
      |> update_job_credential!(%{
        project_credential_id: nil,
        keychain_credential_id: swap_kc.id
      })

      assert {:ok, _updated} = Sandboxes.merge(sandbox, parent, actor)

      reloaded = Repo.reload!(parent_job)

      assert is_nil(reloaded.project_credential_id)

      merged_kc = Repo.get!(KeychainCredential, reloaded.keychain_credential_id)

      assert merged_kc.project_id == parent.id
      assert merged_kc.name == "swap-kc"
      refute merged_kc.id == swap_kc.id
      assert job_scoping_violations(parent, reloaded) == []
    end

    test "switching to a different keychain repoints the parent job" do
      %{actor: actor, parent: parent, kc: parent_kc, job: parent_job} =
        parent_with_job!(:keychain)

      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-swap"})

      other_kc = insert_project_keychain!(sandbox, actor, "kc-other")

      sandbox_job!(sandbox, "Alpha", "A1")
      |> update_job_credential!(%{keychain_credential_id: other_kc.id})

      assert {:ok, _updated} = Sandboxes.merge(sandbox, parent, actor)

      reloaded = Repo.reload!(parent_job)

      merged_kc = Repo.get!(KeychainCredential, reloaded.keychain_credential_id)

      assert merged_kc.project_id == parent.id
      assert merged_kc.name == "kc-other"
      refute reloaded.keychain_credential_id == parent_kc.id
      assert job_scoping_violations(parent, reloaded) == []
    end

    test "switching to a different project credential repoints the parent job" do
      %{actor: actor, parent: parent, job: parent_job} =
        parent_with_job!(:project_credential)

      other_cred =
        insert(:credential, body: %{"token" => "other"}, user: actor)

      other_pc =
        insert(:project_credential, project: parent, credential: other_cred)

      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-swap"})

      sandbox_other_pc = sandbox_project_credential!(sandbox, other_cred.id)

      sandbox_job!(sandbox, "Alpha", "A1")
      |> update_job_credential!(%{project_credential_id: sandbox_other_pc.id})

      assert {:ok, _updated} = Sandboxes.merge(sandbox, parent, actor)

      reloaded = Repo.reload!(parent_job)

      assert reloaded.project_credential_id == other_pc.id
      assert is_nil(reloaded.keychain_credential_id)
      assert job_scoping_violations(parent, reloaded) == []
    end

    test "removing the credential entirely clears it on merge" do
      %{actor: actor, parent: parent, job: parent_job} =
        parent_with_job!(:keychain)

      {:ok, sandbox} = Sandboxes.provision(parent, actor, %{name: "sb-swap"})

      sandbox_job!(sandbox, "Alpha", "A1")
      |> update_job_credential!(%{
        project_credential_id: nil,
        keychain_credential_id: nil
      })

      assert {:ok, _updated} = Sandboxes.merge(sandbox, parent, actor)

      reloaded = Repo.reload!(parent_job)

      assert is_nil(reloaded.project_credential_id)
      assert is_nil(reloaded.keychain_credential_id)
    end
  end
end
