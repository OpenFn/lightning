defmodule LightningWeb.WorkerSocketTest do
  use LightningWeb.ChannelCase, async: true
  alias Lightning.Workers

  describe "connect" do
    test "without a valid token" do
      assert LightningWeb.WorkerSocket |> connect(%{}) == {:error, :unauthorized}

      assert LightningWeb.WorkerSocket |> connect(%{token: "foo"}) ==
               {:error, :unauthorized}
    end

    test "with a valid token" do
      {:ok, bearer, _} =
        Workers.Token.generate_and_sign(
          %{},
          Lightning.Config.worker_token_signer()
        )

      Lightning.Stub.freeze_time(DateTime.utc_now() |> DateTime.add(5, :second))

      assert {:ok, socket} =
               LightningWeb.WorkerSocket
               |> connect(%{
                 token: bearer,
                 worker_version: "1.5.0",
                 api_version: "1.1"
               })

      assert %{token: ^bearer, worker_version: "1.5.0", api_version: "1.1"} =
               socket.assigns
    end
  end
end
