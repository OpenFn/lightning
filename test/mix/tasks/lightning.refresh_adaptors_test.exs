defmodule Mix.Tasks.Lightning.RefreshAdaptorsTest do
  use ExUnit.Case, async: false
  use Mimic

  setup_all do
    Mimic.copy(Lightning.Adaptors)
    :ok
  end

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  describe "bare invocation" do
    test "calls refresh_now/0 and exits 0 on :ok" do
      stub(Lightning.Adaptors, :refresh_now, fn -> :ok end)
      Mix.Tasks.Lightning.RefreshAdaptors.run([])
      assert_received {:mix_shell, :info, [_]}
    end

    test "exits 1 on {:error, :not_leader}" do
      stub(Lightning.Adaptors, :refresh_now, fn -> {:error, :not_leader} end)

      assert catch_exit(Mix.Tasks.Lightning.RefreshAdaptors.run([])) ==
               {:shutdown, 1}

      assert_received {:mix_shell, :error, [_]}
    end

    test "exits 3 on other error" do
      stub(Lightning.Adaptors, :refresh_now, fn -> {:error, :network_down} end)

      assert catch_exit(Mix.Tasks.Lightning.RefreshAdaptors.run([])) ==
               {:shutdown, 3}

      assert_received {:mix_shell, :error, [_]}
    end
  end

  describe "--name flag" do
    test "dispatches to refresh_package/1 with the exact package string" do
      pkg = "@openfn/language-http"
      stub(Lightning.Adaptors, :refresh_package, fn ^pkg -> :ok end)
      Mix.Tasks.Lightning.RefreshAdaptors.run(["--name", pkg])
      assert_received {:mix_shell, :info, [_]}
    end

    test "exits 2 on {:error, :not_found}" do
      stub(Lightning.Adaptors, :refresh_package, fn _pkg ->
        {:error, :not_found}
      end)

      assert catch_exit(
               Mix.Tasks.Lightning.RefreshAdaptors.run([
                 "--name",
                 "@openfn/language-http"
               ])
             ) == {:shutdown, 2}

      assert_received {:mix_shell, :error, [_]}
    end

    test "exits 1 on {:error, :not_leader}" do
      stub(Lightning.Adaptors, :refresh_package, fn _pkg ->
        {:error, :not_leader}
      end)

      assert catch_exit(
               Mix.Tasks.Lightning.RefreshAdaptors.run([
                 "--name",
                 "@openfn/language-http"
               ])
             ) == {:shutdown, 1}

      assert_received {:mix_shell, :error, [_]}
    end

    test "exits 3 on other error" do
      stub(Lightning.Adaptors, :refresh_package, fn _pkg ->
        {:error, :timeout}
      end)

      assert catch_exit(
               Mix.Tasks.Lightning.RefreshAdaptors.run([
                 "--name",
                 "@openfn/language-http"
               ])
             ) == {:shutdown, 3}

      assert_received {:mix_shell, :error, [_]}
    end
  end

  describe "rejected flags" do
    test "raises on unknown --strategy flag" do
      assert_raise OptionParser.ParseError, fn ->
        Mix.Tasks.Lightning.RefreshAdaptors.run(["--strategy", "local"])
      end
    end

    test "raises on unknown --source flag" do
      assert_raise OptionParser.ParseError, fn ->
        Mix.Tasks.Lightning.RefreshAdaptors.run(["--source", "local"])
      end
    end
  end
end
