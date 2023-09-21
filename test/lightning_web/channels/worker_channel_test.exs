defmodule LightningWeb.WorkerChannelTest do
  use LightningWeb.ChannelCase, async: true

  alias Lightning.WorkOrders
  alias Lightning.Workers
  import Lightning.Factories

  describe "joining" do
    test "with an invalid token" do
      assert LightningWeb.UserSocket
             |> socket("socket_id", %{})
             |> subscribe_and_join(LightningWeb.WorkerChannel, "worker:queue") ==
               {:error, %{reason: "unauthorized"}}
    end
  end

  describe "worker:queue channel" do
    setup do
      Lightning.Stub.reset_time()

      {:ok, bearer, _} =
        Workers.Token.generate_and_sign(
          %{},
          Lightning.Config.worker_token_signer()
        )

      Lightning.Stub.freeze_time(DateTime.utc_now() |> DateTime.add(5, :second))

      socket = LightningWeb.WorkerSocket |> socket("socket_id", %{token: bearer})

      {:ok, _, socket} =
        socket |> subscribe_and_join(LightningWeb.WorkerChannel, "worker:queue")

      %{socket: socket}
    end

    test "returns an empty list when there are no attempts", %{socket: socket} do
      ref = push(socket, "claim", %{"demand" => 1})
      assert_reply ref, :ok, %{attempts: []}
    end

    test "returns attempts", %{socket: socket} do
      %{triggers: [trigger]} =
        workflow =
        insert(:simple_workflow)

      Lightning.Stub.reset_time()

      [attempt | rest] =
        1..3
        |> Enum.map(fn _ ->
          {:ok, %{attempts: [attempt]}} =
            WorkOrders.create_for(trigger,
              workflow: workflow,
              dataclip: params_with_assocs(:dataclip)
            )

          attempt
        end)

      %{id: attempt_id} = attempt

      ref = push(socket, "claim", %{"demand" => 1})

      assert_reply ref, :ok, %{
        attempts: [%{"id" => ^attempt_id, "token" => token}]
      }

      Lightning.Stub.freeze_time(DateTime.utc_now() |> DateTime.add(5, :second))

      assert {:ok, claims} =
               Workers.verify_attempt_token(token, %{id: attempt_id})

      assert claims["id"] == attempt_id

      ref = push(socket, "claim", %{"demand" => 4})
      assert_reply ref, :ok, %{attempts: attempts}

      assert attempts |> Enum.map(& &1["id"]) == rest |> Enum.map(& &1.id)
      assert length(attempts) == 2, "only 2 attempts should be returned"
    end
  end
end
