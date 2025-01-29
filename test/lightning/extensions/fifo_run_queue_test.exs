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
