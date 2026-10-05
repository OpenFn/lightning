defmodule Lightning.CLITest do
  use ExUnit.Case, async: true

  use Mimic

  alias Lightning.CLI

  describe "metadata/2" do
    test "passes the state in a file in a private directory, not on the command line" do
      test_pid = self()

      stub(Lightning.OsProcess, :run, fn cmd, args, opts ->
        [_, _, _, "-s", state_path | _] = args

        send(
          test_pid,
          {:run, cmd, args, opts, File.read!(state_path),
           File.stat!(Path.dirname(state_path)).mode}
        )

        {:ok, %{status: 0, out: "", err: ""}}
      end)

      assert {:ok, %CLI.Result{status: 0}} =
               CLI.metadata(%{"foo" => "bar"}, "/tmp/foo")

      assert_received {:run, "/usr/bin/env", args, opts, state_json, mode}

      assert [
               "openfn",
               "metadata",
               "--log-json",
               "-s",
               state_path,
               "-a",
               "/tmp/foo",
               "--log",
               "debug"
             ] = args

      assert state_json == ~s({"foo":"bar"})
      assert Bitwise.band(mode, 0o777) == 0o700
      refute File.exists?(Path.dirname(state_path))
      assert opts[:cleanup_paths] == [Path.dirname(state_path)]

      assert opts[:timeout] == :timer.minutes(2)

      assert %{
               "NODE_PATH" => "./priv/openfn",
               "PATH" => "./priv/openfn/bin:" <> _
             } = opts[:env]
    end

    test "logs the CLI's stderr when it fails, and removes the state" do
      stub(Lightning.OsProcess, :run, fn _cmd, _args, opts ->
        send(self(), {:dir, hd(opts[:cleanup_paths])})
        {:ok, %{status: 1, out: "", err: "Error: Cannot find module 'x'\n"}}
      end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, %CLI.Result{status: 1}} =
                   CLI.metadata(%{}, "/tmp/foo")
        end)

      assert log =~ "openfn metadata exited with status 1"
      assert log =~ "Cannot find module 'x'"
      assert_received {:dir, dir}
      refute File.exists?(dir)
    end

    test "logs a warning with the CLI's stderr on timeout" do
      stub(Lightning.OsProcess, :run, fn _cmd, _args, _opts ->
        {:error, {:timeout, %{out: "", err: "still waiting\n"}}}
      end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:error, :timeout} = CLI.metadata(%{}, "/tmp/foo")
        end)

      assert log =~ "timed out after 120000ms"
      assert log =~ "still waiting"
    end

    test "with correct state" do
      state = %{"foo" => "bar"}
      adaptor_path = "/tmp/foo"

      stdout = """
      {"level":"debug","name":"CLI","message":["Load state..."],"time":1679664658127}
      {"level":"success","name":"CLI","message":["Read state from stdin"],"time":1679664658128}
      {"level":"debug","name":"CLI","message":["state:",{"configuration":{"hostUrl":"****","password":"****","username":"****"}}],"time":1679664658128}
      {"level":"success","name":"CLI","message":["Generating metadata"],"time":1679664658128}
      {"level":"info","name":"CLI","message":["config:",{"hostUrl":"https://play.dhis2.org/2.36.6","password":"district","username":"admin"}],"time":1679664658128}
      {"level":"debug","name":"CLI","message":["config hash: ","b57c9a0c121b0a835b25436133e69221035602da3ff9981e1fcf2d6128aec622"],"time":1679664658128}
      {"level":"debug","name":"CLI","message":["loading adaptor from","/lightning/priv/openfn/lib/node_modules/@openfn/language-dhis2-3.2.8/dist/index.cjs"],"time":1679664658129}
      {"level":"info","name":"CLI","message":["Metadata function found. Generating metadata..."],"time":1679664658252}
      Using latest available version of the DHIS2 api on this server.
      Using latest available version of the DHIS2 api on this server.
      Using latest available version of the DHIS2 api on this server.
      {"level":"success","name":"CLI","message":"Done!"],"time":1679664662562}
      {"message":["/tmp/openfn/repo/meta/b57c9a0c121b0a835b25436133e69221035602da3ff9981e1fcf2d6128aec622.json"]}
      """

      stub(Lightning.OsProcess, :run, fn _cmd, _args, _opts ->
        {:ok, %{status: 0, out: stdout, err: ""}}
      end)

      assert {:ok, res} = CLI.metadata(state, adaptor_path)

      assert res.status == 0
      assert res.end_time - res.start_time >= 0

      last =
        CLI.Result.get_messages(res)
        |> List.last()

      assert last ==
               "/tmp/openfn/repo/meta/b57c9a0c121b0a835b25436133e69221035602da3ff9981e1fcf2d6128aec622.json"
    end
  end
end
