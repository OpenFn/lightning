defmodule Lightning.Extensions.FifoRunQueueTest do
  use Lightning.DataCase, async: true

  alias Lightning.Extensions.FifoRunQueue
  alias Lightning.WorkOrders

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

      actual = FifoRunQueue.claim(1)

      assert match?(
               {:ok, [%{id: ^run1_id, state: :claimed}]},
               actual
             ),
             """
             Expected #{run1_id} to be claimed first
             """

      actual = FifoRunQueue.claim(1)

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
               FifoRunQueue.claim(2)

      assert {:ok, []} = FifoRunQueue.claim(1)
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

      FifoRunQueue.claim(2, "my.worker.name")

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

      FifoRunQueue.claim(2)

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

      {:ok, [%{id: ^run1w1a_id}]} = FifoRunQueue.claim(1)

      # workflow 1a has max concurrency of 1 runs
      {:ok, [%{id: ^run1w1b_id}]} = FifoRunQueue.claim(1)
      {:ok, [%{id: ^run2w1b_id}]} = FifoRunQueue.claim(1)

      # workflow 2a has max concurrency of 1 runs
      {:ok, [%{id: ^run1w2_id}]} = FifoRunQueue.claim(1)
      {:ok, [%{id: ^run2w2_id}]} = FifoRunQueue.claim(1)
      {:ok, [%{id: ^run3w2_id}]} = FifoRunQueue.claim(1)

      {:ok, []} = FifoRunQueue.claim(1)
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

      {:ok, [%{id: ^run1p1_id}]} = FifoRunQueue.claim(1)

      # project 1 has max concurrency of 1 runs
      {:ok, [%{id: ^run1p2_id}]} = FifoRunQueue.claim(1)
      {:ok, [%{id: ^run2p2_id}]} = FifoRunQueue.claim(1)

      # project 2 has max concurrency of 2 runs
      {:ok, [%{id: ^run1p3_id}]} = FifoRunQueue.claim(1)
      {:ok, [%{id: ^run2p3_id}]} = FifoRunQueue.claim(1)
      {:ok, [%{id: ^run3p3_id}]} = FifoRunQueue.claim(1)

      {:ok, []} = FifoRunQueue.claim(1)
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
        FifoRunQueue.claim(3)

      {:ok, [%{id: ^run1p3_id}, %{id: ^run2p3_id}, %{id: ^run3p3_id}]} =
        FifoRunQueue.claim(3)

      {:ok, []} = FifoRunQueue.claim(1)
    end

    # defp fixture_for_workflow({workflow, priority}, index) do
    #   insert_fixtures(workflow, index, priority)
    # end

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

  describe "dequeue" do
    test "deletes the run and any associated run steps" do
      run_1 = insert_run()
      run_2 = insert_run()

      _run_step_1_1 = insert_run_step(run_1)
      _run_step_1_2 = insert_run_step(run_1)
      run_step_2 = insert_run_step(run_2)

      FifoRunQueue.dequeue(run_1)

      assert only_record_for_type?(run_2)

      assert only_record_for_type?(run_step_2)
    end

    test "deletes associated LogLine records" do
      run_1 = build_list(2, :log_line) |> insert_run()

      run_2 = insert_run()
      log_line_2_1 = insert(:log_line, run: run_2)

      FifoRunQueue.dequeue(run_1)

      assert only_record_for_type?(log_line_2_1)
    end

    defp insert_run(log_lines \\ []) do
      insert(:run,
        created_by: build(:user),
        work_order: build(:workorder),
        dataclip: build(:dataclip),
        starting_job: build(:job),
        log_lines: log_lines
      )
    end

    defp insert_run_step(run) do
      insert(:run_step, run: run, step: build(:step))
    end
  end
end
