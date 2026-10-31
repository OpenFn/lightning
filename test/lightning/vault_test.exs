defmodule Lightning.VaultTest do
  use ExUnit.Case, async: true

  test "enforces a primary encryption key" do
    # Vault logs an error for each of these; capture at :emergency so it
    # doesn't pollute test output.
    ExUnit.CaptureLog.with_log([level: :emergency], fn ->
      assert_raise RuntimeError, ~r/Primary encryption key not found/, fn ->
        Lightning.Vault.init([])
      end

      assert_raise RuntimeError,
                   ~r/Encountered an error when decoding the primary encryption key./,
                   fn ->
                     Lightning.Vault.init(primary_encryption_key: "xxx")
                   end

      assert_raise RuntimeError,
                   ~r/Primary encryption key is invalid/,
                   fn ->
                     Lightning.Vault.init(
                       primary_encryption_key:
                         48 |> :crypto.strong_rand_bytes() |> Base.encode64()
                     )
                   end
    end)
  end
end
