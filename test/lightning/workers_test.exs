defmodule Lightning.WorkersTest do
  use ExUnit.Case, async: true

  alias Lightning.Workers.RunToken
  alias Lightning.Workers.WorkerToken

  setup do
    Mox.stub_with(LightningMock, Lightning.API)
    Mox.stub_with(Lightning.MockConfig, Lightning.Config.API)

    %{run_token_signer: Lightning.Config.run_token_signer()}
  end

  describe "WorkerToken" do
    test "can generate a token" do
      {:ok, token, claims} =
        WorkerToken.generate_and_sign(%{"id" => id = Ecto.UUID.generate()})

      assert %{"id" => ^id, "nbf" => nbf} = claims
      assert nbf <= Lightning.current_time() |> DateTime.to_unix()
      assert token != ""

      assert {:ok, claims} = WorkerToken.verify(token)

      assert {:error,
              [
                {:message, "Invalid token"},
                {:claim, "nbf"},
                {:claim_val, _time}
              ]} =
               WorkerToken.validate(claims, %{
                 current_time: DateTime.utc_now() |> DateTime.add(-5, :second)
               })
    end
  end

  describe "RunToken" do
    test "can generate a token", %{run_token_signer: run_token_signer} do
      {:ok, token, claims} =
        RunToken.generate_and_sign(
          %{"id" => id = Ecto.UUID.generate()},
          run_token_signer
        )

      assert %{"id" => ^id, "nbf" => nbf} = claims
      assert nbf <= Lightning.current_time() |> DateTime.to_unix()
      assert token != ""

      assert {:ok, ^claims} =
               RunToken.verify(token, run_token_signer)
    end

    test "validating with a run_id" do
      {:ok, claims} =
        RunToken.generate_claims(%{"id" => id = Ecto.UUID.generate()})

      assert {:ok, ^claims} =
               RunToken.validate(claims, %{
                 id: id,
                 current_time: Lightning.current_time()
               })
    end

    test "validating without a run_id" do
      {:ok, claims} =
        RunToken.generate_claims(%{"id" => _id = Ecto.UUID.generate()})

      assert {:ok, ^claims} =
               RunToken.validate(claims, %{
                 current_time: Lightning.current_time()
               })
    end
  end
end
