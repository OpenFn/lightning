defmodule Lightning.Extensions.FifoRunQueueTest do
  use Lightning.DataCase, async: true

  alias Lightning.Extensions.FifoRunQueue
  alias Lightning.WorkOrders

  @default_queues ["manual", "*"]

  describe "claim" do
    test "claims a run from any project sorting by insertion" do
      project1 = insert(:project)
      project2 = insert(:project)

      %{triggers: [trigger1]} =
        workflow1 =
        insert(:simple_workflow, project: project1) |> with_snapshot()

      %{triggers: [trigger2]} =
        workflow2 =
        insert(:simple_workflow, project: project2) |> with_snapshot()

      {:ok, %{runs: [%{id: run1_id}]}} =
        WorkOrders.create_for(trigger1,
          workflow: workflow1,
          dataclip: params_with_assocs(:dataclip)
        )

      {:ok, %{runs: [%{id: run2_id}]}} =
        WorkOrders.create_for(trigger1,
          workflow: workflow1,
          dataclip: params_with_assocs(:dataclip)
        )

      {:ok, %{runs: [%{id: run3_id}]}} =
        WorkOrders.create_for(trigger2,
          workflow: workflow2,
          dataclip: params_with_assocs(:dataclip)
        )

      {:ok, %{runs: [%{id: run4_id}]}} =
        WorkOrders.create_for(trigger2,
          workflow: workflow2,
          dataclip: params_with_assocs(:dataclip)
        )

      actual = FifoRunQueue.claim(1, nil, @default_queues)

      assert match?(
               {:ok, [%{id: ^run1_id, state: :claimed}]},
               actual
             ),
             """
             Expected #{run1_id} to be claimed first
             """

      actual = FifoRunQueue.claim(1, nil, @default_queues)

      assert match?(
               {:ok, [%{id: ^run2_id, state: :claimed}]},
               actual
             ),
             """
             Expected #{run2_id} to be claimed second
             Got: #{inspect(actual)}
             """

      assert {:ok,
              [
                %{id: ^run3_id, state: :claimed},
                %{id: ^run4_id, state: :claimed}
              ]} =
               FifoRunQueue.claim(2, nil, @default_queues)

      assert {:ok, []} = FifoRunQueue.claim(1, nil, @default_queues)
    end

    test "allows the worker name to be persisted on the claimed run" do
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

      FifoRunQueue.claim(2, "my.worker.name", @default_queues)

      assert %{worker_name: "my.worker.name"} = Lightning.Repo.reload!(run1)
      assert %{worker_name: "my.worker.name"} = Lightning.Repo.reload!(run2)
    end

    test "sets the worker name as nil if none is provided" do
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

      FifoRunQueue.claim(2, nil, @default_queues)

      assert %{worker_name: nil} = Lightning.Repo.reload!(run1)
      assert %{worker_name: nil} = Lightning.Repo.reload!(run2)
    end

    test "is limited by workflow concurrency" do
      [id1, id2] =
        Enum.map(1..2, fn _i -> Ecto.UUID.generate() end)
        |> Enum.sort()

      [project1, project2] =
        [
          insert(:project, id: id1, concurrency: 3),
          insert(:project, id: id2, concurrency: nil)
        ]

      workflow1a = insert(:simple_workflow, project: project1, concurrency: 1)
      workflow1b = insert(:simple_workflow, project: project1, concurrency: 2)
      workflow2 = insert(:simple_workflow, project: project2)

      [
        %{id: run1w1a_id},
        %{id: _run2w1a_id},
        %{id: run1w1b_id},
        %{id: run2w1b_id},
        %{id: _run3w1b_id},
        %{id: run1w2_id},
        %{id: run2w2_id},
        %{id: run3w2_id}
      ] =
        Enum.with_index(
          [
            workflow1a,
            workflow1a,
            workflow1b,
            workflow1b,
            workflow1b,
            workflow2,
            workflow2,
            workflow2
          ],
          &fixture_for_workflow/2
        )

      {:ok, [%{id: ^run1w1a_id}]} =
        FifoRunQueue.claim(1, nil, @default_queues)

      # workflow 1a has max concurrency of 1 runs
      {:ok, [%{id: ^run1w1b_id}]} =
        FifoRunQueue.claim(1, nil, @default_queues)

      {:ok, [%{id: ^run2w1b_id}]} =
        FifoRunQueue.claim(1, nil, @default_queues)

      # workflow 2a has max concurrency of 1 runs
      {:ok, [%{id: ^run1w2_id}]} =
        FifoRunQueue.claim(1, nil, @default_queues)

      {:ok, [%{id: ^run2w2_id}]} =
        FifoRunQueue.claim(1, nil, @default_queues)

      {:ok, [%{id: ^run3w2_id}]} =
        FifoRunQueue.claim(1, nil, @default_queues)

      {:ok, []} = FifoRunQueue.claim(1, nil, @default_queues)
    end

    test "is limited by project concurrency" do
      [id1, id2, id3] =
        Enum.map(1..3, fn _i -> Ecto.UUID.generate() end)
        |> Enum.sort()

      [project1, project2, project3] =
        [
          insert(:project, id: id1, concurrency: 1),
          insert(:project, id: id2, concurrency: 2),
          insert(:project, id: id3, concurrency: nil)
        ]

      workflow1a = insert(:simple_workflow, project: project1)
      workflow2a = insert(:simple_workflow, project: project2)
      workflow3a = insert(:simple_workflow, project: project3)
      workflow1b = insert(:simple_workflow, project: project1)
      workflow2b = insert(:simple_workflow, project: project2)
      workflow3b = insert(:simple_workflow, project: project3)

      [
        %{id: run1p1_id},
        %{id: _run2p1_id},
        %{id: run1p2_id},
        %{id: run2p2_id},
        %{id: _run3p2_id},
        %{id: run1p3_id},
        %{id: run2p3_id},
        %{id: run3p3_id}
      ] =
        Enum.with_index(
          [
            workflow1a,
            workflow1b,
            workflow2a,
            workflow2a,
            workflow2b,
            workflow3a,
            workflow3b,
            workflow3a
          ],
          &fixture_for_workflow/2
        )

      {:ok, [%{id: ^run1p1_id}]} =
        FifoRunQueue.claim(1, nil, @default_queues)

      # project 1 has max concurrency of 1 runs
      {:ok, [%{id: ^run1p2_id}]} =
        FifoRunQueue.claim(1, nil, @default_queues)

      {:ok, [%{id: ^run2p2_id}]} =
        FifoRunQueue.claim(1, nil, @default_queues)

      # project 2 has max concurrency of 2 runs
      {:ok, [%{id: ^run1p3_id}]} =
        FifoRunQueue.claim(1, nil, @default_queues)

      {:ok, [%{id: ^run2p3_id}]} =
        FifoRunQueue.claim(1, nil, @default_queues)

      {:ok, [%{id: ^run3p3_id}]} =
        FifoRunQueue.claim(1, nil, @default_queues)

      {:ok, []} = FifoRunQueue.claim(1, nil, @default_queues)
    end

    test "can claim multiple runs up to project concurrency limit" do
      [id1, id2, id3] =
        Enum.map(1..3, fn _i -> Ecto.UUID.generate() end)
        |> Enum.sort()

      [project1, project2, project3] =
        [
          insert(:project, id: id1, concurrency: 1),
          insert(:project, id: id2, concurrency: 2),
          insert(:project, id: id3, concurrency: nil)
        ]

      workflow1a = insert(:simple_workflow, project: project1)
      workflow2a = insert(:simple_workflow, project: project2)
      workflow3a = insert(:simple_workflow, project: project3)
      workflow1b = insert(:simple_workflow, project: project1)
      workflow2b = insert(:simple_workflow, project: project2)
      workflow3b = insert(:simple_workflow, project: project3)

      [
        %{id: run1p1_id},
        %{id: _run2p1_id},
        %{id: run1p2_id},
        %{id: run2p2_id},
        %{id: _run3p2_id},
        %{id: run1p3_id},
        %{id: run2p3_id},
        %{id: run3p3_id}
      ] =
        Enum.with_index(
          [
            workflow1a,
            workflow1b,
            workflow2a,
            workflow2a,
            workflow2b,
            workflow3a,
            workflow3b,
            workflow3a
          ],
          &fixture_for_workflow/2
        )

      {:ok, [%{id: ^run1p1_id}, %{id: ^run1p2_id}, %{id: ^run2p2_id}]} =
        FifoRunQueue.claim(3, nil, @default_queues)

      {:ok, [%{id: ^run1p3_id}, %{id: ^run2p3_id}, %{id: ^run3p3_id}]} =
        FifoRunQueue.claim(3, nil, @default_queues)

      {:ok, []} = FifoRunQueue.claim(1, nil, @default_queues)
    end

    test "filters by queue in filter mode" do
      project = insert(:project)
      workflow = insert(:simple_workflow, project: project)

      [
        %{id: _default_id},
        %{id: fast_lane_id},
        %{id: _manual_id}
      ] =
        Enum.with_index(
          [{workflow, "default"}, {workflow, "fast_lane"}, {workflow, "manual"}],
          fn {wf, queue}, index ->
            insert_fixtures_with_queue(wf, index, 1, queue)
          end
        )

      {:ok, claimed} =
        FifoRunQueue.claim(10, nil, ["fast_lane"])

      assert [%{id: ^fast_lane_id}] = claimed
    end

    test "preference mode returns all runs and prioritizes named queues" do
      project = insert(:project)
      workflow = insert(:simple_workflow, project: project)

      [
        %{id: default_id},
        %{id: fast_lane_id},
        %{id: manual_id}
      ] =
        Enum.with_index(
          [{workflow, "default"}, {workflow, "fast_lane"}, {workflow, "manual"}],
          fn {wf, queue}, index ->
            insert_fixtures_with_queue(wf, index, 1, queue)
          end
        )

      # Claiming all: all 3 runs should be returned
      {:ok, claimed} =
        FifoRunQueue.claim(10, nil, ["manual", "*"])

      claimed_ids = Enum.map(claimed, & &1.id) |> MapSet.new()

      assert MapSet.equal?(
               claimed_ids,
               MapSet.new([default_id, fast_lane_id, manual_id])
             )

      # Reset: unclaim all runs
      Lightning.Repo.update_all(
        Lightning.Run,
        set: [state: :available, claimed_at: nil]
      )

      # Claiming 1 with ["manual", "*"] should prioritize the manual run
      {:ok, [claimed_one]} =
        FifoRunQueue.claim(1, nil, ["manual", "*"])

      assert claimed_one.id == manual_id
    end

    defp insert_fixtures_with_queue(workflow, index, priority, queue) do
      %{triggers: [trigger]} = workflow

      dataclip = insert(:dataclip)

      wo =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          inserted_at: Timex.shift(Timex.now(), milliseconds: index)
        )

      insert(:run,
        work_order: wo,
        dataclip: dataclip,
        starting_trigger: trigger,
        priority: priority,
        queue: queue
      )
    end

    defp fixture_for_workflow(workflow, index) do
      insert_fixtures(workflow, index, 1)
    end

    defp insert_fixtures(workflow, index, priority) do
      %{triggers: [trigger]} = workflow

      dataclip = insert(:dataclip)

      wo =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          inserted_at: Timex.shift(Timex.now(), milliseconds: index)
        )

      insert(:run,
        work_order: wo,
        dataclip: dataclip,
        starting_trigger: trigger,
        priority: priority
      )
    end
  end
end
