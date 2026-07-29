defmodule LightningWeb.ProjectLive.CliSettingsTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  setup :stub_usage_limiter_ok
  setup :register_and_log_in_user

  defp project_for(user, role) do
    insert(:project,
      name: "my-cli-project",
      project_users: [%{user: user, role: role}]
    )
  end

  describe "CLI tab" do
    test "shows the script that pulls this project onto your machine", %{
      conn: conn,
      user: user
    } do
      project = project_for(user, :admin)

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project}/settings#cli", on_error: :raise)

      assert html =~ "Command line interface"

      script =
        view
        |> element("#cli-setup-script pre")
        |> render()

      assert script =~ "npm install -g @openfn/cli"
      assert script =~ "mkdir -p my-cli-project"
      assert script =~ "OPENFN_ENDPOINT=#{LightningWeb.Endpoint.url()}"
      assert script =~ "OPENFN_API_KEY="
      assert script =~ "openfn project pull #{project.id}"
    end

    test "shows the commands for syncing changes both ways", %{
      conn: conn,
      user: user
    } do
      project = project_for(user, :admin)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings#cli", on_error: :raise)

      script = view |> element("#cli-sync-script pre") |> render()

      assert script =~ "openfn project pull"
      assert script =~ "openfn project deploy --dry-run"
      assert script =~ "openfn project deploy"
    end

    test "links to the page where access tokens are generated", %{
      conn: conn,
      user: user
    } do
      project = project_for(user, :admin)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings#cli", on_error: :raise)

      assert has_element?(
               view,
               ~s{#cli-create-token-link[href="/profile/tokens"]}
             )
    end

    test "both scripts can be copied to the clipboard", %{
      conn: conn,
      user: user
    } do
      project = project_for(user, :admin)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings#cli", on_error: :raise)

      for id <- ["cli-setup-script", "cli-sync-script"] do
        button =
          view
          |> element(~s{##{id}-copy-button[phx-hook="Copy"]})
          |> render()

        assert button =~ "openfn project"
      end
    end

    test "tells viewers they cannot deploy from the CLI", %{
      conn: conn,
      user: user
    } do
      project = project_for(user, :viewer)

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project}/settings#cli", on_error: :raise)

      assert html =~ "Role based permissions"

      assert html =~
               "workflows from the CLI, but you can still pull a copy."

      # pulling is still available to them
      assert view |> element("#cli-setup-script pre") |> render() =~
               "openfn project pull #{project.id}"
    end
  end
end
