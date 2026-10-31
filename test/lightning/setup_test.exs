defmodule Lightning.SetupTest do
  use Lightning.DataCase, async: false

  import ExUnit.CaptureLog
  import Mimic

  describe "with_minimum_setup/1" do
    setup :set_mimic_from_context

    setup do
      level = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: level) end)
      :ok
    end

    test "announces the catalogue load and warns when it fails" do
      stub(Lightning.Adaptors, :ensure_loaded, fn -> {:error, :timeout} end)

      log =
        capture_log(fn ->
          assert {:ok, :done, _} =
                   Lightning.Setup.with_minimum_setup(fn -> :done end)
        end)

      assert log =~ "Loading the adaptor catalogue"
      assert log =~ ":timeout"
      assert log =~ "ADAPTORS.md"
    end
  end
end
