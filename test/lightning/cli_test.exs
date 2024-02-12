defmodule Lightning.CLITest do
  use ExUnit.Case, async: true

  alias Lightning.CLI

  test "any command" do
    CLI.execute("foo")

    assert {"foo",
            [
              timeout: nil,
              log: true,
              env: %{
                "NODE_PATH" => "./priv/openfn",
                "PATH" => "./priv/openfn/bin:" <> _
              }
            ]} = expect_command()
  end

  describe "metadata/2" do
    test "with incorrect state" do
      state = %{"foo" => "bar"}
      adaptor_path = "/tmp/foo"

      FakeRambo.Helpers.stub_run(
        {:ok,
         %{
           status: 1,
           out:
             "{\"level\":\"debug\",\"name\":\"CLI\",\"message\":[\"Load state...\"]}\n{\"level\":\"success\",\"name\":\"CLI\",\"message\":[\"Read state from stdin\"]}\n{\"level\":\"debug\",\"name\":\"CLI\",\"message\":[\"state:\",{}]}\n{\"level\":\"success\",\"name\":\"CLI\",\"message\":[\"Generating metadata\"]}\n{\"level\":\"info\",\"name\":\"CLI\",\"message\":[\"config:\",null]}\n",
           err:
             "{\"level\":\"error\",\"name\":\"CLI\",\"message\":[\"ERROR: Invalid configuration passed\"]}\n"
         }}
      )

      res = CLI.metadata(state, adaptor_path)

      expected_command =
        ~s(openfn metadata --log-json -S '{"foo":"bar"}' -a #{adaptor_path} --log debug)

      {command, opts} = expect_command()

      assert command == expected_command

      assert [
               timeout: nil,
               log: true,
               env: %{
                 "NODE_PATH" => "./priv/openfn",
                 "PATH" => "./priv/openfn/bin:" <> _
               }
             ] = opts

      assert res
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

      FakeRambo.Helpers.stub_run({:ok, %{status: 0, out: stdout, err: ""}})

      res = CLI.metadata(state, adaptor_path)

      assert res.status == 0
      assert res.end_time - res.start_time >= 0

      assert CLI.Result.get_messages(res) == [
               "/tmp/openfn/repo/meta/b57c9a0c121b0a835b25436133e69221035602da3ff9981e1fcf2d6128aec622.json"
             ]
    end
  end

  defp expect_command do
    assert_received {"/usr/bin/env", ["sh", "-c", command], opts}

    {command, opts}
  end
end
