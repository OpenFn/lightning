defmodule Lightning.Workflows.EdgeTest do
  use Lightning.DataCase

  alias Lightning.Workflows.Edge

  describe "changeset/2" do
    test "valid changeset" do
      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: Ecto.UUID.generate(),
          condition: :on_job_success
        })

      assert changeset.valid?
    end

    test "edges must have a condition" do
      changeset = Edge.changeset(%Edge{}, %{workflow_id: Ecto.UUID.generate()})

      refute changeset.valid?

      assert changeset.errors == [
               condition: {"can't be blank", [validation: :required]}
             ]
    end

    test "trigger sourced edges must have the :always condition" do
      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: Ecto.UUID.generate(),
          source_trigger_id: Ecto.UUID.generate(),
          condition: "on_job_success"
        })

      refute changeset.valid?

      assert {:condition,
              {"must be :always when source is a trigger",
               [validation: :inclusion, enum: [:always]]}} in changeset.errors
    end

    test "can't have both source_job_id and source_trigger_id" do
      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: Ecto.UUID.generate(),
          source_job_id: Ecto.UUID.generate(),
          source_trigger_id: Ecto.UUID.generate()
        })

      refute changeset.valid?

      assert {:source_job_id,
              {"source_job_id and source_trigger_id are mutually exclusive", []}} in changeset.errors,
             "error on the first change in the case both are set"

      changeset =
        Edge.changeset(%Edge{source_job_id: Ecto.UUID.generate()}, %{
          workflow_id: Ecto.UUID.generate(),
          source_trigger_id: Ecto.UUID.generate()
        })

      refute changeset.valid?

      assert {
               :source_trigger_id,
               {"source_job_id and source_trigger_id are mutually exclusive", []}
             } in changeset.errors
    end

    test "can't set the target job to the same as the source job" do
      job_id = Ecto.UUID.generate()

      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: Ecto.UUID.generate(),
          source_job_id: job_id,
          condition: :on_job_success,
          target_job_id: job_id
        })

      refute changeset.valid?

      assert {
               :target_job_id,
               {"target_job_id must be different from source_job_id", []}
             } in changeset.errors

      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: Ecto.UUID.generate(),
          source_job_id: job_id,
          condition: :on_job_success,
          target_job_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
    end

    test "can't assign a node from a different workflow" do
      workflow = Lightning.WorkflowsFixtures.workflow_fixture()
      job = Lightning.JobsFixtures.job_fixture()

      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: workflow.id,
          condition: :on_job_success,
          source_job_id: job.id
        })

      {:error, changeset} = Repo.insert(changeset)

      refute changeset.valid?

      assert {
               :source_job_id,
               {"job doesn't exist, or is not in the same workflow",
                [
                  constraint: :foreign,
                  constraint_name: "workflow_edges_source_job_id_fkey"
                ]}
             } in changeset.errors

      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: workflow.id,
          condition: :on_job_success,
          target_job_id: job.id
        })

      {:error, changeset} = Repo.insert(changeset)

      refute changeset.valid?

      assert {
               :target_job_id,
               {"job doesn't exist, or is not in the same workflow",
                [
                  constraint: :foreign,
                  constraint_name: "workflow_edges_target_job_id_fkey"
                ]}
             } in changeset.errors

      trigger =
        Lightning.Workflows.Trigger.changeset(
          %Lightning.Workflows.Trigger{},
          %{
            name: "test",
            workflow_id: job.workflow_id
          }
        )
        |> Repo.insert!()

      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: workflow.id,
          condition: :always,
          source_trigger_id: trigger.id
        })

      {:error, changeset} = Repo.insert(changeset)

      refute changeset.valid?

      assert {
               :source_trigger_id,
               {"trigger doesn't exist, or is not in the same workflow",
                [
                  constraint: :foreign,
                  constraint_name: "workflow_edges_source_trigger_id_fkey"
                ]}
             } in changeset.errors
    end

    test "new edges are enabled by default" do
      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: Ecto.UUID.generate(),
          target_job_id: Ecto.UUID.generate(),
          condition: :on_job_success
        })

      assert changeset.valid?

      assert changeset.data.enabled ||
               Map.get(changeset.changes, :enabled, true),
             "New edges should be enabled by default"
    end

    test "edges with source_trigger_id should be enabled regardless of job's enabled status" do
      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: Ecto.UUID.generate(),
          source_trigger_id: Ecto.UUID.generate(),
          target_job_id: Ecto.UUID.generate(),
          condition: :always
        })

      assert changeset.valid?

      assert changeset.data.enabled ||
               Map.get(changeset.changes, :enabled, true),
             "Edges with a source_trigger_id should always be enabled"
    end
  end
end
