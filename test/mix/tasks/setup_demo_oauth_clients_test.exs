defmodule Mix.Tasks.Lightning.SetupDemoOauthClientsTest do
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

  describe "run/1 --list" do
    test "shows configured and not_configured clients" do
      with_oauth_config(gmail: [client_id: "id", client_secret: "secret"])

      output =
        capture_io(fn ->
          Mix.Tasks.Lightning.SetupDemoOauthClients.run(["--list"])
        end)

      assert output =~ "Ready to create:"
      assert output =~ "gmail"
      assert output =~ "Missing OAuth client configuration:"
      assert output =~ "google_drive"
      assert output =~ "1 configured, 9 missing configuration"
    end

    test "shows all configured when all env vars set" do
      with_oauth_config()

      output =
        capture_io(fn ->
          Mix.Tasks.Lightning.SetupDemoOauthClients.run(["--list"])
        end)

      assert output =~ "Ready to create:"
      assert output =~ "10 configured, 0 missing configuration"
      refute output =~ "Missing OAuth client configuration:"
    end
  end

  describe "run/1 creating clients" do
    setup do
      with_oauth_config()
    end

    test "creates all configured OAuth clients" do
      %{super_user: _user} =
        SetupUtils.create_users(create_super: true)
        |> SetupUtils.confirm_users()

      output =
        capture_io(fn ->
          Mix.Tasks.Lightning.SetupDemoOauthClients.run([])
        end)

      assert output =~ "Created:"
      assert output =~ "Google Sheets"
      assert output =~ "Gmail"
      assert output =~ "Salesforce"
      assert output =~ "Created 10, skipped 0, not configured 0"
    end

    test "--only filters to specified clients" do
      %{super_user: _user} =
        SetupUtils.create_users(create_super: true)
        |> SetupUtils.confirm_users()

      output =
        capture_io(fn ->
          Mix.Tasks.Lightning.SetupDemoOauthClients.run([
            "--only",
            "google_sheets,salesforce"
          ])
        end)

      assert output =~ "Google Sheets"
      assert output =~ "Salesforce"
      assert output =~ "Created 2, skipped 0, not configured 0"
    end

    test "--only with invalid key raises" do
      assert_raise Mix.Error, ~r/Unknown client key/, fn ->
        Mix.Tasks.Lightning.SetupDemoOauthClients.run([
          "--only",
          "bogus_service"
        ])
      end
    end

    test "raises on unknown options" do
      assert_raise Mix.Error, ~r/Unknown option/, fn ->
        Mix.Tasks.Lightning.SetupDemoOauthClients.run(["--foo"])
      end
    end

    test "raises when no users exist" do
      assert_raise Mix.Error, ~r/No users found/, fn ->
        capture_io(fn ->
          Mix.Tasks.Lightning.SetupDemoOauthClients.run([])
        end)
      end
    end

    test "raises when --user email not found" do
      %{super_user: _user} =
        SetupUtils.create_users(create_super: true)
        |> SetupUtils.confirm_users()

      assert_raise Mix.Error, ~r/User not found with email/, fn ->
        capture_io(fn ->
          Mix.Tasks.Lightning.SetupDemoOauthClients.run([
            "--user",
            "nonexistent@example.com"
          ])
        end)
      end
    end
  end
end
