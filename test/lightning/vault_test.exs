defmodule Lightning.VaultTest do
  use ExUnit.Case, async: true

  # Change the log level to something higher than the logged error
  # from Vault, so we don't pollute our test output.
  setup do
    current_level = Logger.level()
    Logger.configure(level: :emergency)

    on_exit(fn ->
      Logger.configure(level: current_level)
    end)
  end

  @tag :capture_log
  test "enforces a primary encryption key" do
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
  end
end
