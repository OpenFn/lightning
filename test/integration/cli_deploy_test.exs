# This module will be re-introduced in https://github.com/OpenFn/Lightning/issues/1143
defmodule Lightning.CliDeployTest do
  use LightningWeb.ConnCase, async: false

  require Logger

  alias Lightning.AccountsFixtures
  import Lightning.JobsFixtures
  import Lightning.Factories

  alias Lightning.Accounts

  describe "The openfn CLI can be used to" do
    setup do
      host = Application.get_env(:lightning, LightningWeb.Endpoint)[:url][:host]
      port = Application.get_env(:lightning, LightningWeb.Endpoint)[:http][:port]
      user = AccountsFixtures.user_fixture()
      token = Accounts.generate_api_token(user)

      File.write(
        "./tmp/testConfig.json",
        "{
          \"endpoint\": \"http://#{host}:#{port}/api/provision\",
          \"apiKey\": \"#{token}\",
          \"projectSpec\": \"./tmp/testProjectSpec.yaml\",
          \"projectState\": \"./tmp/testProjectState.json\"
        }"
      )

      %{user: user}
    end

    test "pull a valid project from a Lightning server", %{user: user} do
      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: "admin"}]
        )

      %{triggers: [%{id: webhook_trigger_id}]} =
        insert(:complex_workflow, project: project)

      # Check version
      System.cmd(
        "openfn",
        ["--version"],
        into: IO.stream()
      )

      # Try to pull
      System.cmd(
        "openfn",
        ["pull", project.id, "-c", "./tmp/testConfig.json"]
      )

      # Check result
      assert File.read("./tmp/testProjectSpec.yaml") == {:ok, expectedYaml()}
      assert File.read("./tmp/testProjectSpec.yaml") == {:ok, expectedState()}
    end

    test "deploy a new project to a Lightning server", %{user: user} do
      # System.cmd(
      #   "openfn",
      #   ["deploy", "-c", "./tmp/testConfig.json"],
      #   into: IO.stream()
      # )
    end

    test "deploy updates to an existing project on a Lightning server", %{
      user: user
    } do
      # System.cmd(
      #   "openfn",
      #   ["deploy", "-c", "./tmp/testConfig.json"],
      #   into: IO.stream()
      # )
    end
  end

  defp expectedYaml do
    """
    blahBlahBlah
    """
  end

  defp expectedState do
    """
    {"moreblah": true}
    """
  end
end
