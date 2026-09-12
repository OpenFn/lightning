defmodule Lightning.Workflows.WorkflowReleasesTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Workflows.WorkflowRelease
  alias Lightning.Workflows.WorkflowReleases

  describe "insert_release/2" do
    setup do
      workflow = insert(:workflow)
      snapshot = insert(:snapshot, workflow: workflow)
      %{workflow: workflow, snapshot: snapshot, user: insert(:user)}
    end

    test "allocates sequential version numbers per workflow", %{
      workflow: workflow,
      snapshot: snapshot,
      user: user
    } do
      base = %{
        workflow_id: workflow.id,
        kind: :go_live,
        snapshot_id: snapshot.id,
        published_by_id: user.id
      }

      assert {:ok, %WorkflowRelease{version_number: 1, kind: :go_live}} =
               WorkflowReleases.insert_release(Repo, base)

      assert {:ok, %WorkflowRelease{version_number: 2}} =
               WorkflowReleases.insert_release(Repo, base)

      # A different workflow keeps its own sequence.
      other = insert(:workflow)
      other_snapshot = insert(:snapshot, workflow: other)

      assert {:ok, %WorkflowRelease{version_number: 1}} =
               WorkflowReleases.insert_release(Repo, %{
                 workflow_id: other.id,
                 kind: :go_live,
                 snapshot_id: other_snapshot.id
               })
    end

    test "enforces uniqueness of version_number within a workflow", %{
      workflow: workflow,
      snapshot: snapshot
    } do
      attrs = %{
        workflow_id: workflow.id,
        version_number: 1,
        kind: :go_live,
        snapshot_id: snapshot.id
      }

      assert {:ok, _} =
               %WorkflowRelease{}
               |> WorkflowRelease.changeset(attrs)
               |> Repo.insert()

      assert {:error, changeset} =
               %WorkflowRelease{}
               |> WorkflowRelease.changeset(attrs)
               |> Repo.insert()

      assert %{version_number: ["exists for this workflow"]} =
               errors_on(changeset)
    end
  end

  describe "list_for_workflow/1" do
    test "returns releases newest first with associations preloaded" do
      workflow = insert(:workflow)
      snapshot = insert(:snapshot, workflow: workflow)
      user = insert(:user)
      source = insert(:project)

      {:ok, _v1} =
        WorkflowReleases.insert_release(Repo, %{
          workflow_id: workflow.id,
          kind: :go_live,
          snapshot_id: snapshot.id,
          published_by_id: user.id
        })

      {:ok, _v2} =
        WorkflowReleases.insert_release(Repo, %{
          workflow_id: workflow.id,
          kind: :promote,
          snapshot_id: snapshot.id,
          published_by_id: user.id,
          source_project_id: source.id
        })

      assert [
               %WorkflowRelease{
                 version_number: 2,
                 kind: :promote,
                 published_by: %{id: publisher_id},
                 source_project: %{id: source_id},
                 snapshot: %{id: snapshot_id}
               },
               %WorkflowRelease{version_number: 1, kind: :go_live}
             ] = WorkflowReleases.list_for_workflow(workflow.id)

      assert publisher_id == user.id
      assert source_id == source.id
      assert snapshot_id == snapshot.id
    end
  end

  describe "get_by_version_number/2" do
    test "returns the release for that version_number with its snapshot preloaded" do
      workflow = insert(:workflow)
      # lock_version deliberately differs from the version_number the lookup keys
      # on.
      snapshot = insert(:snapshot, workflow: workflow, lock_version: 7)
      user = insert(:user)

      {:ok, release} =
        WorkflowReleases.insert_release(Repo, %{
          workflow_id: workflow.id,
          kind: :go_live,
          snapshot_id: snapshot.id,
          published_by_id: user.id
        })

      assert %WorkflowRelease{
               id: id,
               version_number: 1,
               snapshot: %{id: snapshot_id, lock_version: 7}
             } = WorkflowReleases.get_by_version_number(workflow, 1)

      assert id == release.id
      assert snapshot_id == snapshot.id

      # Accepts a workflow id as well as a struct.
      assert %WorkflowRelease{id: ^id} =
               WorkflowReleases.get_by_version_number(workflow.id, 1)
    end

    test "returns nil when the workflow has no release with that version_number" do
      workflow = insert(:workflow)

      assert WorkflowReleases.get_by_version_number(workflow, 99) == nil
    end
  end
end
