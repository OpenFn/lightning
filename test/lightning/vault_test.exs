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

  test "enforces a primary encryption key" do
    assert_raise RuntimeError, fn ->
      Lightning.Vault.init([])
    end
  end
end
