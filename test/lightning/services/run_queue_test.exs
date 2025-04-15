defmodule Lightning.Services.RunQueueTest do
  use Lightning.DataCase, async: true

  alias Lightning.Repo
  alias Lightning.Services.RunQueue
  alias Lightning.WorkOrders

  describe "claim/2" do
    test "persists the worker name when claiming a run" do
      worker_name = "my.worker.name"

      project1 = insert(:project)

      %{triggers: [trigger1]} =
        workflow1 =
        insert(:simple_workflow, project: project1) |> with_snapshot()

      {:ok, %{runs: [run1]}} =
        WorkOrders.create_for(trigger1,
          workflow: workflow1,
          dataclip: params_with_assocs(:dataclip)
        )

      {:ok, %{runs: [run2]}} =
        WorkOrders.create_for(trigger1,
          workflow: workflow1,
          dataclip: params_with_assocs(:dataclip)
        )

      RunQueue.claim(2, worker_name)

      assert %{worker_name: ^worker_name} = Repo.reload!(run1)
      assert %{worker_name: ^worker_name} = Repo.reload!(run2)
    end
  end
end
