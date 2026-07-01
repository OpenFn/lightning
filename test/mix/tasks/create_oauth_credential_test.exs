defmodule Mix.Tasks.Lightning.CreateOauthCredentialTest do
  use Lightning.DataCase, async: false

  import ExUnit.CaptureIO

  alias Lightning.SetupUtils

  @test_oauth_config [
    google_drive: [client_id: "test-gd-id", client_secret: "test-gd-secret"],
    google_sheets: [
      client_id: "test-gs-id",
      client_secret: "test-gs-secret"
    ],
    gmail: [client_id: "test-gm-id", client_secret: "test-gm-secret"],
    salesforce: [client_id: "test-sf-id", client_secret: "test-sf-secret"],
    salesforce_sandbox: [
      client_id: "test-sfs-id",
      client_secret: "test-sfs-secret"
    ],
    microsoft_sharepoint: [
      client_id: "test-sp-id",
      client_secret: "test-sp-secret"
    ],
    microsoft_outlook: [
      client_id: "test-ol-id",
      client_secret: "test-ol-secret"
    ],
    microsoft_calendar: [
      client_id: "test-cal-id",
      client_secret: "test-cal-secret"
    ],
    microsoft_onedrive: [
      client_id: "test-od-id",
      client_secret: "test-od-secret"
    ],
    microsoft_teams: [
      client_id: "test-tm-id",
      client_secret: "test-tm-secret"
    ]
  ]

  defp with_oauth_config(config \\ @test_oauth_config) do
    previous = Application.get_env(:lightning, :demo_oauth_clients)
    Application.put_env(:lightning, :demo_oauth_clients, config)

    on_exit(fn ->
      Application.put_env(:lightning, :demo_oauth_clients, previous)
    end)
  end

  defp create_user_and_clients do
    with_oauth_config()

    %{super_user: user} =
      SetupUtils.create_users(create_super: true)
      |> SetupUtils.confirm_users()

    clients =
      SetupUtils.create_demo_oauth_clients(user, only: [:gmail, :google_sheets])

    %{user: user, clients: clients}
  end

  describe "run/1 --list" do
    test "shows available OAuth clients" do
      %{clients: clients} = create_user_and_clients()

      output =
        capture_io(fn ->
          Mix.Tasks.Lightning.CreateOauthCredential.run(["--list"])
        end)

      assert output =~ "Available OAuth clients:"
      assert output =~ clients.gmail.name
      assert output =~ "ID:"
    end

    test "shows empty message when no clients exist" do
      output =
        capture_io(fn ->
          Mix.Tasks.Lightning.CreateOauthCredential.run(["--list"])
        end)

      assert output =~ "No OAuth clients found"
      assert output =~ "setup_demo_oauth_clients"
    end
  end

  describe "run/1 creating credentials" do
    test "creates credential by client name" do
      %{clients: clients} = create_user_and_clients()

      output =
        capture_io(fn ->
          Mix.Tasks.Lightning.CreateOauthCredential.run([
            "--client",
            clients.gmail.name
          ])
        end)

      assert output =~ "Created credential: Gmail - demo"
      assert output =~ "OAuth client: Gmail"
      assert output =~ "placeholder tokens"
    end

    test "creates credential with custom --name" do
      %{clients: clients} = create_user_and_clients()

      output =
        capture_io(fn ->
          Mix.Tasks.Lightning.CreateOauthCredential.run([
            "--client",
            clients.gmail.name,
            "--name",
            "My Custom Gmail"
          ])
        end)

      assert output =~ "Created credential: My Custom Gmail"
    end

    test "creates credential attached to --project" do
      %{user: user, clients: clients} = create_user_and_clients()

      {:ok, project} =
        Lightning.Projects.create_project(%{
          name: "test-project",
          project_users: [%{user_id: user.id, role: :owner}]
        })

      output =
        capture_io(fn ->
          Mix.Tasks.Lightning.CreateOauthCredential.run([
            "--client",
            clients.gmail.name,
            "--project",
            project.id
          ])
        end)

      assert output =~ "Created credential:"
      assert output =~ "Project: #{project.id}"
    end

    test "raises when --client is missing" do
      assert_raise Mix.Error, ~r/--client is required/, fn ->
        Mix.Tasks.Lightning.CreateOauthCredential.run([])
      end
    end

    test "raises when client not found and shows available clients" do
      %{clients: _clients} = create_user_and_clients()

      error =
        assert_raise Mix.Error, ~r/No OAuth client found/, fn ->
          capture_io(fn ->
            Mix.Tasks.Lightning.CreateOauthCredential.run([
              "--client",
              "Nonexistent Service"
            ])
          end)
        end

      assert error.message =~ "Available OAuth clients:"
      assert error.message =~ "Gmail"
    end

    test "raises when no users exist" do
      # With no clients and no users, client lookup fails first.
      # The error indicates no clients exist yet.
      assert_raise Mix.Error, ~r/No OAuth client found/, fn ->
        capture_io(fn ->
          Mix.Tasks.Lightning.CreateOauthCredential.run([
            "--client",
            "anything"
          ])
        end)
      end
    end

    test "raises when --user email not found" do
      %{clients: clients} = create_user_and_clients()

      assert_raise Mix.Error, ~r/User not found with email/, fn ->
        capture_io(fn ->
          Mix.Tasks.Lightning.CreateOauthCredential.run([
            "--client",
            clients.gmail.name,
            "--user",
            "nonexistent@example.com"
          ])
        end)
      end
    end

    test "raises on unknown options" do
      assert_raise Mix.Error, ~r/Unknown option/, fn ->
        Mix.Tasks.Lightning.CreateOauthCredential.run(["--bogus"])
      end
    end
  end
end
