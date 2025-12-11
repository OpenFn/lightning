defmodule Lightning.Workflows.WorkflowTest do
  alias Lightning.Workflows
  use Lightning.DataCase, async: true

  alias Lightning.Workflows
  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.Trigger

  import Lightning.Factories

  describe "relationships" do
    test "should be able resolve the current snapshot" do
      {:ok, workflow} =
        insert(:simple_workflow, project: insert(:project))
        |> Workflow.touch()
        |> Workflows.save_workflow(insert(:user))

      assert from(s in Ecto.assoc(workflow, :snapshots),
               where: s.lock_version == ^workflow.lock_version
             )
             |> Repo.one()
    end
  end

  describe "changeset/2 basic validations" do
    test "requires name and valid concurrency" do
      p = insert(:project)

      # missing name
      cs = Workflow.changeset(%Workflow{}, %{project_id: p.id})
      refute cs.valid?
      assert "can't be blank" in errors_on(cs).name

      # bad concurrency
      cs2 =
        Workflow.changeset(%Workflow{}, %{
          name: "w",
          project_id: p.id,
          concurrency: 0
        })

      refute cs2.valid?
      assert "must be greater than or equal to 1" in errors_on(cs2).concurrency

      # ok
      cs3 =
        Workflow.changeset(%Workflow{}, %{
          name: "w",
          project_id: p.id,
          concurrency: 2
        })

      assert cs3.valid?
    end

    test "assoc_constraint(:project)" do
      cs =
        Workflow.changeset(%Workflow{}, %{
          name: "w",
          project_id: Ecto.UUID.generate()
        })

      {:error, cs} = Repo.insert(cs)
      assert "does not exist" in errors_on(cs).project
    end

    test "unique name per project" do
      p1 = insert(:project)
      p2 = insert(:project)

      {:ok, _} =
        %Workflow{}
        |> Workflow.changeset(%{name: "w1", project_id: p1.id})
        |> Repo.insert()

      # same name in same project -> error
      {:error, cs} =
        %Workflow{}
        |> Workflow.changeset(%{name: "w1", project_id: p1.id})
        |> Repo.insert()

      assert "A workflow with this name already exists (possibly pending deletion) in this project." in errors_on(
               cs
             ).name

      # same name in different project -> ok
      assert {:ok, _} =
               %Workflow{}
               |> Workflow.changeset(%{name: "w1", project_id: p2.id})
               |> Repo.insert()
    end
  end

  describe "workflow_activated?/1" do
    test "true when a new trigger is enabled" do
      p = insert(:project)

      cs =
        %Workflow{}
        |> Workflow.changeset(%{
          name: "w",
          project_id: p.id,
          triggers: [%{type: :webhook, enabled: true}]
        })

      assert Workflow.workflow_activated?(cs)
    end

    test "true when an existing trigger flips enabled from false -> true" do
      wf = insert(:workflow, name: "w", project: insert(:project))
      t = insert(:trigger, workflow: wf, type: :webhook, enabled: false)

      # PRELOAD!
      wf = Repo.preload(wf, :triggers)

      t_cs =
        t
        |> Repo.reload!()
        |> Trigger.changeset(%{enabled: true})

      cs =
        wf
        |> Workflow.changeset(%{})
        |> Ecto.Changeset.put_assoc(:triggers, [t_cs])

      assert Workflow.workflow_activated?(cs)
    end

    test "false when no triggers are being enabled" do
      wf = insert(:workflow, project: insert(:project))
      t = insert(:trigger, workflow: wf, type: :webhook, enabled: true)

      # PRELOAD!
      wf = Repo.preload(wf, :triggers)

      t_cs =
        t
        |> Repo.reload!()
        # no change
        |> Trigger.changeset(%{})

      cs =
        wf
        |> Workflow.changeset(%{})
        |> Ecto.Changeset.put_assoc(:triggers, [t_cs])

      refute Workflow.workflow_activated?(cs)
    end
  end

  describe "touch/1 and soft delete" do
    test "touch increments lock_version and updates updated_at" do
      # safely in the past
      old = ~U[2000-01-01 00:00:00Z]
      wf = insert(:workflow, lock_version: 0, updated_at: old)

      updated = wf |> Workflow.touch() |> Repo.update!()

      assert updated.lock_version == wf.lock_version + 1
      assert DateTime.compare(updated.updated_at, old) == :gt
    end

    test "request_deletion_changeset allows setting deleted_at" do
      wf = insert(:workflow)
      now = DateTime.utc_now()

      {:ok, updated} =
        wf
        |> Workflow.request_deletion_changeset(%{deleted_at: now})
        |> Repo.update()

      assert updated.deleted_at
    end
  end

  test "version_history defaults to []" do
    wf = insert(:workflow)
    assert wf.version_history == []
  end
end
