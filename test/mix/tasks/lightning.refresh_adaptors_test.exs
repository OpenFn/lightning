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
    test "calls refresh/2 with await: true and exits 0 on {:ok, counts}, reporting them" do
      stub(Lightning.Adaptors, :refresh, fn Lightning.Adaptors, opts ->
        assert Keyword.fetch!(opts, :await) == true
        assert Keyword.fetch!(opts, :timeout) == :timer.minutes(10)
        {:ok, %{listed: 109, changed: 4, fetched: 4, errors: 1}}
      end)

      Mix.Tasks.Lightning.RefreshAdaptors.run([])
      assert_received {:mix_shell, :info, [_]}
      assert_received {:mix_shell, :info, [msg]}
      assert msg =~ "listed 109"
      assert msg =~ "fetched 4"
      assert msg =~ "errors 1"
    end

    test "exits 2 when the cycle succeeds but the source listed no adaptors" do
      stub(Lightning.Adaptors, :refresh, fn _sup, _opts ->
        {:ok, %{listed: 0, changed: 0, fetched: 0, errors: 0}}
      end)

      assert catch_exit(Mix.Tasks.Lightning.RefreshAdaptors.run([])) ==
               {:shutdown, 2}

      assert_received {:mix_shell, :error, [_]}
    end

    test "exits 2 on {:error, :timeout}" do
      stub(Lightning.Adaptors, :refresh, fn _sup, _opts -> {:error, :timeout} end)

      assert catch_exit(Mix.Tasks.Lightning.RefreshAdaptors.run([])) ==
               {:shutdown, 2}

      assert_received {:mix_shell, :error, [_]}
    end

    test "exits 2 on other error" do
      stub(Lightning.Adaptors, :refresh, fn _sup, _opts ->
        {:error, :network_down}
      end)

      assert catch_exit(Mix.Tasks.Lightning.RefreshAdaptors.run([])) ==
               {:shutdown, 2}

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

    test "exits 1 on {:error, :not_found}" do
      stub(Lightning.Adaptors, :refresh_package, fn _pkg ->
        {:error, :not_found}
      end)

      assert catch_exit(
               Mix.Tasks.Lightning.RefreshAdaptors.run([
                 "--name",
                 "@openfn/language-http"
               ])
             ) == {:shutdown, 1}

      assert_received {:mix_shell, :error, [_]}
    end

    test "exits 2 on other error" do
      stub(Lightning.Adaptors, :refresh_package, fn _pkg ->
        {:error, :timeout}
      end)

      assert catch_exit(
               Mix.Tasks.Lightning.RefreshAdaptors.run([
                 "--name",
                 "@openfn/language-http"
               ])
             ) == {:shutdown, 2}

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
