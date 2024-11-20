defmodule Lightning.Workflows.WorkflowTest do
  alias Lightning.Workflows
  use Lightning.DataCase, async: true

  alias Lightning.Workflows
  alias Lightning.Workflows.Workflow

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
end
