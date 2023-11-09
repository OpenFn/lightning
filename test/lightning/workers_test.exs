defmodule Lightning.WorkersTest do
  use ExUnit.Case, async: true

  alias Lightning.Workers.Token

  describe "Token" do
    test "can generate a token" do
      {:ok, token, claims} =
        Token.generate_and_sign(%{"id" => id = Ecto.UUID.generate()})

      assert %{"id" => ^id, "nbf" => nbf} = claims
      assert nbf <= DateTime.utc_now() |> DateTime.to_unix()
      assert token != ""

      assert {:ok, claims} = Token.verify(token)

      assert {:error,
              [
                {:message, "Invalid token"},
                {:claim, "nbf"},
                {:claim_val, _time}
              ]} =
               Token.validate(claims, %{
                 current_time: DateTime.utc_now() |> DateTime.add(-5, :second)
               })
    end
  end
end
