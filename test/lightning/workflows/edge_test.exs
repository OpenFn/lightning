defmodule Lightning.Workflows.EdgeTest do
  use Lightning.DataCase

  alias Lightning.Workflows.Edge

  describe "changeset/2" do
    test "valid changeset" do
      changeset = Edge.changeset(%Edge{}, %{workflow_id: Ecto.UUID.generate()})
      assert changeset.valid?
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
        Lightning.Jobs.Trigger.changeset(%Lightning.Jobs.Trigger{}, %{
          name: "test",
          workflow_id: job.workflow_id
        })
        |> Repo.insert!()

      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: workflow.id,
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
  end
end
