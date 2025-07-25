defmodule Lightning.Workflows.SnapshotTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows.Snapshot

  import Lightning.Factories

  describe "build/1" do
    test "includes keychain_credential_id in snapshot when job has keychain credential" do
      workflow = insert(:workflow)

      keychain_credential =
        insert(:keychain_credential, project: workflow.project)

      insert(:job, workflow: workflow, keychain_credential: keychain_credential)

      changeset = Snapshot.build(workflow)

      assert changeset.valid?
      assert %{jobs: [job_snapshot]} = changeset.changes

      assert job_snapshot.changes.keychain_credential_id ==
               keychain_credential.id
    end

    test "includes project_credential_id in snapshot when job has project credential" do
      workflow = insert(:workflow)
      project_credential = insert(:project_credential, project: workflow.project)

      insert(:job, workflow: workflow, project_credential: project_credential)

      changeset = Snapshot.build(workflow)

      assert changeset.valid?
      assert %{jobs: [job_snapshot]} = changeset.changes
      assert job_snapshot.changes.project_credential_id == project_credential.id
    end

    test "includes both credential fields as nil when job has no credentials" do
      workflow = insert(:workflow)

      insert(:job, workflow: workflow)

      changeset = Snapshot.build(workflow)

      assert changeset.valid?
      assert %{jobs: [job_snapshot]} = changeset.changes
      refute Map.has_key?(job_snapshot.changes, :project_credential_id)
      refute Map.has_key?(job_snapshot.changes, :keychain_credential_id)
    end
  end

  describe "create/1" do
    test "creates snapshot successfully with keychain credential" do
      workflow = insert(:workflow)

      keychain_credential =
        insert(:keychain_credential, project: workflow.project)

      insert(:job, workflow: workflow, keychain_credential: keychain_credential)

      assert {:ok, snapshot} = Snapshot.create(workflow)
      assert [job_snapshot] = snapshot.jobs
      assert job_snapshot.keychain_credential_id == keychain_credential.id
    end
  end
end
