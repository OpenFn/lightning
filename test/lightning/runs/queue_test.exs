defmodule Lightning.Runs.QueueTest do
  use Lightning.DataCase, async: true

  alias Lightning.Runs.Query
  alias Lightning.Runs.Queue
  alias Lightning.WorkOrders

  describe "worker name and session config" do
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

    test "if worker name is provided, persists it for each claimed run",
         %{
           run_1: run_1,
           run_2: run_2
         } do
      Queue.claim(2, Query.eligible_for_claim(), "my.worker.name")

      assert %{worker_name: "my.worker.name"} =
               Lightning.Repo.reload!(run_1)

      assert %{worker_name: "my.worker.name"} =
               Lightning.Repo.reload!(run_2)
    end

    test "if no worker name is provided, persists nil for each claimed run",
         %{
           run_1: run_1,
           run_2: run_2
         } do
      Queue.claim(2, Query.eligible_for_claim())

      assert %{worker_name: nil} = Lightning.Repo.reload!(run_1)
      assert %{worker_name: nil} = Lightning.Repo.reload!(run_2)
    end

    test "configures session with work_mem when configured", %{
      run_1: _run_1
    } do
      prev = Application.get_env(:lightning, :claim_work_mem)

      try do
        Application.put_env(:lightning, :claim_work_mem, "64MB")

        ref =
          :telemetry_test.attach_event_handlers(self(), [
            [:lightning, :repo, :query]
          ])

        Queue.claim(1, Query.eligible_for_claim())

        assert_receive {[:lightning, :repo, :query], ^ref, _measurements,
                        %{query: "SET LOCAL plan_cache_mode" <> _}}

        assert_receive {[:lightning, :repo, :query], ^ref, _measurements,
                        %{query: "SET LOCAL work_mem = '64MB'"}}
      after
        if prev,
          do: Application.put_env(:lightning, :claim_work_mem, prev),
          else: Application.delete_env(:lightning, :claim_work_mem)
      end
    end

    test "skips work_mem when nil", %{run_1: _run_1} do
      prev = Application.get_env(:lightning, :claim_work_mem)

      try do
        Application.put_env(:lightning, :claim_work_mem, nil)

        ref =
          :telemetry_test.attach_event_handlers(self(), [
            [:lightning, :repo, :query]
          ])

        Queue.claim(1, Query.eligible_for_claim())

        assert_receive {[:lightning, :repo, :query], ^ref, _measurements,
                        %{query: "SET LOCAL plan_cache_mode" <> _}}

        refute_receive {[:lightning, :repo, :query], ^ref, _measurements,
                        %{query: "SET LOCAL work_mem" <> _}},
                       100
      after
        if prev,
          do: Application.put_env(:lightning, :claim_work_mem, prev),
          else: Application.delete_env(:lightning, :claim_work_mem)
      end
    end
  end

  describe "queue filtering and ordering" do
    setup do
      project = insert(:project)

      %{triggers: [trigger]} =
        workflow =
        insert(:simple_workflow, project: project) |> with_snapshot()

      # Create runs with different queue values using direct insert
      # so we can control the queue field precisely.
      # Using second offsets from a fixed base time to ensure
      # deterministic insertion order.
      base_time = DateTime.utc_now()

      runs =
        Enum.map(
          [
            {"default", 0},
            {"fast_lane", 1},
            {"manual", 2},
            {"fast_lane", 3},
            {"default", 4}
          ],
          fn {queue, offset} ->
            ts = DateTime.add(base_time, offset, :second)
            dataclip = insert(:dataclip)

            wo =
              insert(:workorder,
                workflow: workflow,
                trigger: trigger,
                dataclip: dataclip,
                inserted_at: ts
              )

            insert(:run,
              work_order: wo,
              dataclip: dataclip,
              starting_trigger: trigger,
              queue: queue,
              inserted_at: ts
            )
          end
        )

      [default1, fast_lane1, manual1, fast_lane2, default2] = runs

      %{
        default1: default1,
        default2: default2,
        fast_lane1: fast_lane1,
        fast_lane2: fast_lane2,
        manual1: manual1
      }
    end

    test "filter mode returns only runs matching the named queues", %{
      fast_lane1: fast_lane1,
      fast_lane2: fast_lane2
    } do
      {:ok, claimed} =
        Queue.claim(
          10,
          Query.eligible_for_claim(),
          nil,
          ["fast_lane"]
        )

      claimed_ids = Enum.map(claimed, & &1.id) |> MapSet.new()

      assert MapSet.equal?(
               claimed_ids,
               MapSet.new([fast_lane1.id, fast_lane2.id])
             )
    end

    test "filter mode returns empty when no matching runs exist" do
      {:ok, claimed} =
        Queue.claim(
          10,
          Query.eligible_for_claim(),
          nil,
          ["nonexistent_queue"]
        )

      assert claimed == []
    end

    test "filter mode with multiple named queues returns matching runs",
         %{
           fast_lane1: fast_lane1,
           fast_lane2: fast_lane2,
           manual1: manual1
         } do
      {:ok, claimed} =
        Queue.claim(
          10,
          Query.eligible_for_claim(),
          nil,
          ["fast_lane", "manual"]
        )

      claimed_ids = Enum.map(claimed, & &1.id) |> MapSet.new()

      assert MapSet.equal?(
               claimed_ids,
               MapSet.new([fast_lane1.id, fast_lane2.id, manual1.id])
             )
    end

    test "preference mode returns all runs", %{
      manual1: manual1,
      default1: default1,
      default2: default2,
      fast_lane1: fast_lane1,
      fast_lane2: fast_lane2
    } do
      {:ok, claimed} =
        Queue.claim(
          10,
          Query.eligible_for_claim(),
          nil,
          ["manual", "*"]
        )

      claimed_ids = Enum.map(claimed, & &1.id) |> MapSet.new()

      # All 5 runs should be returned (no filtering)
      assert MapSet.equal?(
               claimed_ids,
               MapSet.new([
                 manual1.id,
                 default1.id,
                 default2.id,
                 fast_lane1.id,
                 fast_lane2.id
               ])
             )
    end

    test "preference mode prioritizes named queues when demand is limited",
         %{manual1: manual1} do
      # With demand=1, the manual run should be claimed first
      # because ["manual", "*"] gives it queue preference position 1
      {:ok, [claimed]} =
        Queue.claim(
          1,
          Query.eligible_for_claim(),
          nil,
          ["manual", "*"]
        )

      assert claimed.id == manual1.id
    end

    test "preference mode with multiple named queues prioritizes correctly",
         %{
           fast_lane1: fast_lane1,
           fast_lane2: fast_lane2
         } do
      # With ["fast_lane", "manual", "*"], fast_lane gets priority 1,
      # manual gets priority 2, everything else gets 3.
      # Claiming 2 should yield the two fast_lane runs.
      {:ok, claimed} =
        Queue.claim(
          2,
          Query.eligible_for_claim(),
          nil,
          ["fast_lane", "manual", "*"]
        )

      claimed_ids = Enum.map(claimed, & &1.id) |> MapSet.new()

      assert MapSet.equal?(
               claimed_ids,
               MapSet.new([fast_lane1.id, fast_lane2.id])
             )
    end

    test "default queues return all runs with manual prioritized",
         %{manual1: manual1} do
      # Default is ["manual", "*"]. Claiming 1 should get the manual run.
      {:ok, [claimed]} =
        Queue.claim(1, Query.eligible_for_claim())

      assert claimed.id == manual1.id
    end
  end
end
