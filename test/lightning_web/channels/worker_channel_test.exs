defmodule LightningWeb.WorkerChannelTest do
  use LightningWeb.ChannelCase, async: true

  alias Lightning.WorkOrders
  alias Lightning.Workers
  import Lightning.Factories

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
      ref = push(socket, "claim", %{"demand" => 1})
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

      ref = push(socket, "claim", %{"demand" => 1})

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

      ref = push(socket, "claim", %{"demand" => 4})
      assert_reply ref, :ok, %{runs: runs}

      assert runs |> Enum.map(& &1["id"]) |> MapSet.new() ==
               rest |> Enum.map(& &1.id) |> MapSet.new()

      assert length(runs) == 2, "only 2 runs should be returned"
    end
  end
end
