defmodule LightningWeb.ProjectLive.GithubSyncUiTest do
  @moduledoc """
  Tests for the Sync tab UI on project settings: the new connection form (title,
  searchable dropdowns, legacy format switch) and the connected-state panel.
  """

  use LightningWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Lightning.Factories
  import Lightning.GithubHelpers
  import Mox

  setup :stub_usage_limiter_ok
  setup :verify_on_exit!

  @installation %{
    "id" => "1234",
    "account" => %{"type" => "User", "login" => "username"}
  }

  @switch "#toggle-legacy-format-switch"
  @sync_version_input ~s{input[name="connection[sync_version]"]}

  defp open_new_connection_form(conn) do
    project = insert(:project)
    {conn, user} = setup_project_user(conn, project, :admin)
    set_valid_github_oauth_token!(user)

    expect_get_user_installations(200, %{"installations" => [@installation]})
    expect_create_installation_token(@installation["id"])
    expect_get_installation_repos(200, %{"repositories" => []})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/settings#vcs")
    render_async(view)

    view
  end

  defp stub_failed_verification do
    Mox.stub(Lightning.Tesla.Mock, :call, fn _env, _opts ->
      {:ok, %Tesla.Env{status: 404, body: %{"something" => "not right"}}}
    end)
  end

  defp open_connected_panel(conn, role, connection_attrs) do
    project = insert(:project)
    {conn, _user} = setup_project_user(conn, project, role)

    insert(
      :project_repo_connection,
      Keyword.merge(
        [
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234"
        ],
        connection_attrs
      )
    )

    stub_failed_verification()

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/settings#vcs")

    {view, render_async(view)}
  end

  describe "new connection form" do
    test "shows the title and the docs banner", %{conn: conn} do
      view = open_new_connection_form(conn)

      assert has_element?(view, "h6", "Configure Two-Way Sync to GitHub")

      assert has_element?(
               view,
               ~s{#project-repo-connection-form a[href="https://docs.openfn.org/documentation/link-to-GitHub"]}
             )
    end

    test "repository and branch dropdowns are searchable, installation is not",
         %{conn: conn} do
      view = open_new_connection_form(conn)

      assert has_element?(
               view,
               "#select-repos-input-searchable input[data-select-search]"
             )

      assert has_element?(
               view,
               "#select-branches-input-searchable input[data-select-search]"
             )

      refute has_element?(view, "#select-installations-input-searchable")
    end

    test "defaults to the v2 format with the legacy switch off", %{conn: conn} do
      view = open_new_connection_form(conn)

      assert has_element?(view, "#{@switch}[aria-checked=false]")
      assert has_element?(view, ~s{#{@sync_version_input}[value=true]})
    end

    test "flipping the switch selects the legacy format and flips it back",
         %{conn: conn} do
      view = open_new_connection_form(conn)

      view |> element(@switch) |> render_click()

      assert has_element?(view, "#{@switch}[aria-checked=true]")
      assert has_element?(view, ~s{#{@sync_version_input}[value=false]})

      view |> element(@switch) |> render_click()

      assert has_element?(view, "#{@switch}[aria-checked=false]")
      assert has_element?(view, ~s{#{@sync_version_input}[value=true]})
    end

    test "the legacy choice survives changing a dropdown", %{conn: conn} do
      view = open_new_connection_form(conn)

      view |> element(@switch) |> render_click()

      view
      |> form("#project-repo-connection-form")
      |> render_change(
        connection: %{github_installation_id: @installation["id"]}
      )

      assert has_element?(view, "#{@switch}[aria-checked=true]")
      assert has_element?(view, ~s{#{@sync_version_input}[value=false]})
    end

    test "the switch is hidden when importing from GitHub", %{conn: conn} do
      view = open_new_connection_form(conn)

      assert has_element?(view, @switch)

      view
      |> form("#project-repo-connection-form")
      |> render_change(connection: %{sync_direction: "deploy"})

      refute has_element?(view, @switch)
    end
  end

  describe "connected panel" do
    test "v2 connections show the title and no legacy note or config path",
         %{conn: conn} do
      {view, html} = open_connected_panel(conn, :admin, sync_version: true)

      assert has_element?(view, "h6", "Connected to GitHub")
      refute html =~ "legacy sync format"
      refute html =~ "Path to config"
      refute html =~ "Sync version:"
    end

    test "v1 connections show the legacy note and the config path",
         %{conn: conn} do
      {view, html} = open_connected_panel(conn, :admin, sync_version: false)

      assert has_element?(view, "h6", "Connected to GitHub")

      assert html =~
               "This connection uses the legacy sync format (config.json). Reconnect to update to v2 sync formats"

      assert html =~ "Path to config"
    end

    test "admins get a remove integration button next to the sync button",
         %{conn: conn} do
      {view, _html} = open_connected_panel(conn, :admin, sync_version: true)

      assert has_element?(
               view,
               "#remove-integration-button",
               "Remove integration"
             )

      assert has_element?(view, "#initiate-sync-button")
      assert has_element?(view, "#remove_connection_modal")
    end

    test "editors can't remove the integration", %{conn: conn} do
      {view, _html} = open_connected_panel(conn, :editor, sync_version: true)

      refute has_element?(view, "#remove-integration-button")
      refute has_element?(view, "#remove_connection_modal")
    end

    test "the verification banner renders inside the connected card",
         %{conn: conn} do
      {view, _html} = open_connected_panel(conn, :admin, sync_version: true)

      assert has_element?(view, "#verify-connection-banner")

      # the banner is a descendant of the card that holds the title
      assert has_element?(
               view,
               "div.bg-white:has(h6) #verify-connection-banner"
             )
    end
  end
end
