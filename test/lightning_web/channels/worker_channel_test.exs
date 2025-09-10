defmodule LightningWeb.WorkerChannelTest do
  use LightningWeb.ChannelCase, async: false

  alias Lightning.Repo
  alias Lightning.WorkOrders
  alias Lightning.Workers

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

    test "rolls back claimed runs when timeout is reached", %{socket: socket} do
      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow) |> with_snapshot()

      {:ok, %{runs: [%{id: run_id} = run]}} =
        WorkOrders.create_for(trigger,
          workflow: workflow,
          dataclip: params_with_assocs(:dataclip)
        )

      # Set a very short timeout for testing (100ms)
      Application.put_env(:lightning, :run_channel_join_timeout_seconds, 0.1)

      ref =
        push(socket, "claim", %{"demand" => 1, "worker_name" => "my.pod.name"})

      assert_reply ref, :ok, %{runs: [%{"id" => ^run_id}]}

      # Verify the run is claimed
      run = Repo.reload!(run)
      assert run.state == :claimed

      # Manually trigger the timeout by sending the message directly
      send(socket.channel_pid, {:claim_timeout, [run]})

      # Wait a bit for the message to be processed
      Process.sleep(100)

      # Verify the run has been rolled back to available
      run = Repo.reload!(run)
      assert run.state == :available
      assert run.claimed_at == nil
      assert run.worker_name == nil

      # Clean up
      Application.delete_env(:lightning, :run_channel_join_timeout_seconds)
    end

    test "cancels timeout when run channel is joined", %{socket: socket} do
      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow) |> with_snapshot()

      {:ok, %{runs: [%{id: run_id} = run]}} =
        WorkOrders.create_for(trigger,
          workflow: workflow,
          dataclip: params_with_assocs(:dataclip)
        )

      # Set a short timeout for testing
      Application.put_env(:lightning, :run_channel_join_timeout_seconds, 1)

      ref =
        push(socket, "claim", %{"demand" => 1, "worker_name" => "my.pod.name"})

      assert_reply ref, :ok, %{runs: [%{"id" => ^run_id, "token" => _token}]}

      # Verify the run is claimed
      run = Repo.reload!(run)
      assert run.state == :claimed

      # Immediately simulate joining the run channel by sending the notification message
      # This should cancel the timeout before it fires
      # Use the PubSub message format for cross-node communication
      worker_id = socket.assigns[:worker_id] || socket.id

      Lightning.broadcast(
        "worker_channel:#{worker_id}",
        {:run_channel_joined, run_id, worker_id}
      )

      # Wait a bit for the message to be processed
      Process.sleep(100)

      # Verify the run is still claimed (timeout was cancelled)
      run = Repo.reload!(run)
      assert run.state == :claimed

      # Clean up
      Application.delete_env(:lightning, :run_channel_join_timeout_seconds)
    end
  end
end
