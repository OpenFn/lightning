defmodule LightningWeb.WorkerChannelTest do
  use LightningWeb.ChannelCase, async: false

  alias Lightning.Repo
  alias Lightning.WorkOrders
  alias Lightning.Workers
  alias LightningWeb.WorkerPresence

  import Lightning.Factories

  # this ensures the WorkAvailable server inherits the mox stubs
  setup :set_mox_from_context

  describe "joining" do
    test "with an invalid claim" do
      assert LightningWeb.WorkerSocket
             |> socket("socket_id", %{})
             |> subscribe_and_join(LightningWeb.WorkerChannel, "worker:queue") ==
               {:error, %{reason: "unauthorized"}}

      assert LightningWeb.WorkerSocket
             |> socket("socket_id", %{token: "foo"})
             |> subscribe_and_join(LightningWeb.WorkerChannel, "worker:queue") ==
               {:error, %{reason: "unauthorized"}}
    end

    test "tracks worker presence with default capacity" do
      {:ok, bearer, claims} =
        Workers.WorkerToken.generate_and_sign(
          %{},
          Lightning.Config.worker_token_signer()
        )

      socket =
        LightningWeb.WorkerSocket
        |> socket("socket_id", %{token: bearer, claims: claims})

      {:ok, _, _socket} =
        socket |> subscribe_and_join(LightningWeb.WorkerChannel, "worker:queue")

      # Give presence a moment to sync
      Process.sleep(50)

      assert WorkerPresence.total_worker_capacity() == 1
    end

    test "tracks worker presence with custom capacity" do
      {:ok, bearer, claims} =
        Workers.WorkerToken.generate_and_sign(
          %{},
          Lightning.Config.worker_token_signer()
        )

      socket =
        LightningWeb.WorkerSocket
        |> socket("socket_id", %{token: bearer, claims: claims})

      {:ok, _, _socket} =
        socket
        |> subscribe_and_join(LightningWeb.WorkerChannel, "worker:queue", %{
          "capacity" => 10
        })

      # Give presence a moment to sync
      Process.sleep(50)

      assert WorkerPresence.total_worker_capacity() == 10
    end
  end

  describe "worker:queue channel" do
    setup do
      {:ok, bearer, claims} =
        Workers.WorkerToken.generate_and_sign(
          %{},
          Lightning.Config.worker_token_signer()
        )

      socket =
        LightningWeb.WorkerSocket
        |> socket("socket_id", %{token: bearer, claims: claims})

      {:ok, _, socket} =
        socket |> subscribe_and_join(LightningWeb.WorkerChannel, "worker:queue")

      %{socket: socket}
    end

    test "returns an empty list when there are no runs", %{socket: socket} do
      ref =
        push(socket, "claim", %{"demand" => 1, "worker_name" => "my.pod.name"})

      assert_reply ref, :ok, %{runs: []}
    end

    test "returns runs", %{socket: socket} do
      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow) |> with_snapshot()

      Lightning.Stub.reset_time()

      [run | rest] =
        1..3
        |> Enum.map(fn _ ->
          {:ok, %{runs: [run]}} =
            WorkOrders.create_for(trigger,
              workflow: workflow,
              dataclip: params_with_assocs(:dataclip)
            )

          run
        end)

      %{id: run_id} = run

      ref =
        push(socket, "claim", %{"demand" => 1, "worker_name" => "my.pod.name"})

      assert_reply ref,
                   :ok,
                   %{
                     runs: [%{"id" => ^run_id, "token" => token}]
                   },
                   1_000

      Lightning.Stub.freeze_time(DateTime.utc_now() |> DateTime.add(5, :second))

      assert {:ok, claims} =
               Workers.verify_run_token(token, %{id: run_id})

      assert claims["id"] == run_id

      ref =
        push(socket, "claim", %{"demand" => 4, "worker_name" => "my.pod.name"})

      assert_reply ref, :ok, %{runs: runs}

      assert runs |> Enum.map(& &1["id"]) |> MapSet.new() ==
               rest |> Enum.map(& &1.id) |> MapSet.new()

      assert length(runs) == 2, "only 2 runs should be returned"
    end

    test "updates the run with the provided worker name", %{socket: socket} do
      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow) |> with_snapshot()

      {:ok, %{runs: [%{id: run_id} = run]}} =
        WorkOrders.create_for(trigger,
          workflow: workflow,
          dataclip: params_with_assocs(:dataclip)
        )

      ref =
        push(socket, "claim", %{"demand" => 1, "worker_name" => "my.pod.name"})

      assert_reply ref, :ok, %{runs: [%{"id" => ^run_id}]}

      run = Repo.reload!(run)

      assert run.worker_name == "my.pod.name"
    end

    test "if given an empty string for a worker name stores it as nil", %{
      socket: socket
    } do
      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow) |> with_snapshot()

      {:ok, %{runs: [%{id: run_id} = run]}} =
        WorkOrders.create_for(trigger,
          workflow: workflow,
          dataclip: params_with_assocs(:dataclip)
        )

      ref = push(socket, "claim", %{"demand" => 1, "worker_name" => ""})

      assert_reply ref, :ok, %{runs: [%{"id" => ^run_id}]}

      assert %{worker_name: nil} = Repo.reload!(run)
    end

    test "claim with explicit queues parameter filters runs", %{
      socket: socket
    } do
      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow) |> with_snapshot()

      # Create a run with default queue via WorkOrders
      {:ok, %{runs: [%{id: _default_run_id}]}} =
        WorkOrders.create_for(trigger,
          workflow: workflow,
          dataclip: params_with_assocs(:dataclip)
        )

      # Create a fast_lane run directly
      dataclip = insert(:dataclip)

      wo =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      fast_lane_run =
        insert(:run,
          work_order: wo,
          dataclip: dataclip,
          starting_trigger: trigger,
          queue: "fast_lane"
        )

      fast_lane_id = fast_lane_run.id

      # Claim with filter mode for fast_lane only
      ref =
        push(socket, "claim", %{
          "demand" => 10,
          "worker_name" => "my.pod.name",
          "queues" => ["fast_lane"]
        })

      assert_reply ref, :ok, %{runs: runs}, 1_000

      assert [%{"id" => ^fast_lane_id}] = runs
    end

    test "claim without queues parameter uses default preference mode",
         %{socket: socket} do
      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow) |> with_snapshot()

      # Create a default-queue run
      {:ok, %{runs: [%{id: default_run_id}]}} =
        WorkOrders.create_for(trigger,
          workflow: workflow,
          dataclip: params_with_assocs(:dataclip)
        )

      # Create a manual-queue run
      dataclip = insert(:dataclip)

      wo =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      manual_run =
        insert(:run,
          work_order: wo,
          dataclip: dataclip,
          starting_trigger: trigger,
          queue: "manual"
        )

      manual_run_id = manual_run.id

      # Claim without queues -- defaults to ["manual", "*"]
      # This uses preference mode, so all runs should be returned
      ref =
        push(socket, "claim", %{
          "demand" => 10,
          "worker_name" => "my.pod.name"
        })

      assert_reply ref, :ok, %{runs: runs}, 1_000

      run_ids = Enum.map(runs, & &1["id"])

      # Both runs should be claimed (preference mode returns all)
      assert manual_run_id in run_ids
      assert default_run_id in run_ids
    end

    test "malformed queues parameter falls back to default", %{
      socket: socket
    } do
      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow) |> with_snapshot()

      {:ok, %{runs: [%{id: run_id}]}} =
        WorkOrders.create_for(trigger,
          workflow: workflow,
          dataclip: params_with_assocs(:dataclip)
        )

      # Non-list value
      ref =
        push(socket, "claim", %{
          "demand" => 1,
          "worker_name" => "my.pod.name",
          "queues" => "fast_lane"
        })

      assert_reply ref, :ok, %{runs: [%{"id" => ^run_id}]}

      # Re-create a new available run since the previous was claimed
      {:ok, %{runs: [%{id: run_id2}]}} =
        WorkOrders.create_for(trigger,
          workflow: workflow,
          dataclip: params_with_assocs(:dataclip)
        )

      # Empty list
      ref =
        push(socket, "claim", %{
          "demand" => 1,
          "worker_name" => "my.pod.name",
          "queues" => []
        })

      assert_reply ref, :ok, %{runs: [%{"id" => ^run_id2}]}

      # Re-create a new available run
      {:ok, %{runs: [%{id: run_id3}]}} =
        WorkOrders.create_for(trigger,
          workflow: workflow,
          dataclip: params_with_assocs(:dataclip)
        )

      # List with non-strings
      ref =
        push(socket, "claim", %{
          "demand" => 1,
          "worker_name" => "my.pod.name",
          "queues" => [1, 2]
        })

      assert_reply ref, :ok, %{runs: [%{"id" => ^run_id3}]}
    end
  end
end
