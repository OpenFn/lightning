defmodule Lightning.Runs.QueueTest do
  use Lightning.DataCase, async: true

  alias Lightning.Runs.Query
  alias Lightning.Runs.Queue
  alias Lightning.WorkOrders

  setup do
    project1 = insert(:project)

    %{triggers: [trigger1]} =
      workflow1 =
      insert(:simple_workflow, project: project1) |> with_snapshot()

    {:ok, %{runs: [run_1]}} =
      WorkOrders.create_for(trigger1,
        workflow: workflow1,
        dataclip: params_with_assocs(:dataclip)
      )

    {:ok, %{runs: [run_2]}} =
      WorkOrders.create_for(trigger1,
        workflow: workflow1,
        dataclip: params_with_assocs(:dataclip)
      )

    %{run_1: run_1, run_2: run_2}
  end

  test "if worker name is provided, persists it for each claimed run", %{
    run_1: run_1,
    run_2: run_2
  } do
    Queue.claim(2, Query.eligible_for_claim(), "my.worker.name")

    assert %{worker_name: "my.worker.name"} = Lightning.Repo.reload!(run_1)
    assert %{worker_name: "my.worker.name"} = Lightning.Repo.reload!(run_2)
  end

  test "if no worker name is provided, persists nil for each claimed run", %{
    run_1: run_1,
    run_2: run_2
  } do
    Queue.claim(2, Query.eligible_for_claim())

    assert %{worker_name: nil} = Lightning.Repo.reload!(run_1)
    assert %{worker_name: nil} = Lightning.Repo.reload!(run_2)
  end
end
