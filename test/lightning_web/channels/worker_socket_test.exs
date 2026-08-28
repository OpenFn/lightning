defmodule LightningWeb.WorkerSocketTest do
  use LightningWeb.ChannelCase, async: true

  import Lightning.TokenHelpers

  describe "connect" do
    test "without a valid token" do
      assert LightningWeb.WorkerSocket |> connect(%{}) == {:error, :unauthorized}

      assert LightningWeb.WorkerSocket |> connect(%{token: "foo"}) ==
               {:error, :unauthorized}
    end

    test "with a valid token" do
      bearer = ws_worker_token()

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

    # THE ws-worker compatibility guard, at the surface a worker actually meets, and
    # with its twin in test/lightning/workers/worker_token_test.exs the most
    # important test in this suite. A real worker token carries worker_id, iat
    # and iss and NO nbf — so nbf must never join @worker_token_claims, because
    # doing that goes green in CI and disconnects every deployed worker.
    test "with a token shaped exactly like @openfn/ws-worker 1.27.4's" do
      socket =
        LightningWeb.WorkerSocket
        |> connect(%{
          token: ws_worker_token(),
          worker_version: "1.27.4",
          api_version: "1.2"
        })
        |> assert_accepted(
          "WorkerSocket.connect/2 refused the exact claim set every worker in the " <>
            "field sends. Shipping this disconnects every deployed worker."
        )

      assert %{
               "worker_id" => "curly-parrot-jumps",
               "iss" => "urn:openfn:worker"
             } = socket.assigns.claims

      # The other half of the guard: what just connected carries no nbf.
      refute Map.has_key?(socket.assigns.claims, "nbf")
    end
  end
end
