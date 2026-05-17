defmodule LightningWeb.ProjectLive.SandboxSettingsTest do
  use LightningWeb.ConnCase, async: true
  use Mimic

  import Phoenix.LiveViewTest
  import Lightning.Factories

  setup :stub_usage_limiter_ok
  setup :register_and_log_in_user

  setup do
    Mimic.copy(Lightning.Projects.Sandboxes)
    :ok
  end

  defp setup_parent_and_sandbox(%{user: user}) do
    parent =
      insert(:project,
        name: "parent-project",
        project_users: [%{user: user, role: :owner}]
      )

    sandbox =
      insert(:project,
        name: "sandbox-test",
        parent: parent,
        project_users: [%{user: user, role: :owner}]
      )

    {:ok, parent: parent, sandbox: sandbox}
  end

  describe "non-sandbox project (parent project)" do
    setup [:setup_parent_and_sandbox]

    test "does not show any sandbox banners", %{conn: conn, parent: parent} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{parent.id}/settings")

      refute html =~ "sandbox-banner-"
    end

    test "shows 'Project Identity' header on project tab", %{
      conn: conn,
      parent: parent
    } do
      {:ok, _view, html} = live(conn, ~p"/projects/#{parent.id}/settings")
      assert html =~ "Project Identity"
      refute html =~ "Sandbox Identity"
    end

    test "shows the danger zone delete button", %{conn: conn, parent: parent} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{parent.id}/settings")
      assert html =~ "The danger zone"
      assert html =~ "Delete project"
    end

    test "shows webhook auth methods table on webhook_security tab", %{
      conn: conn,
      parent: parent
    } do
      {:ok, _view, html} = live(conn, ~p"/projects/#{parent.id}/settings")
      refute html =~ "Webhook authentication is managed in the parent project"
    end
  end

  describe "sandbox project" do
    setup [:setup_parent_and_sandbox]

    test "shows Editable banner on credentials and collections tabs", %{
      conn: conn,
      sandbox: sandbox
    } do
      {:ok, _view, html} = live(conn, ~p"/projects/#{sandbox.id}/settings")

      assert html =~ ~s(id="sandbox-banner-credentials")
      assert html =~ ~s(id="sandbox-banner-collections")

      assert html =~
               "Changes you make here will sync to the parent project on merge."
    end

    test "shows Local banner on project, collaboration, vcs, data-storage, history-exports tabs",
         %{conn: conn, sandbox: sandbox} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{sandbox.id}/settings")

      for tab <- ~w(project collaboration vcs data-storage history-exports) do
        assert html =~ ~s(id="sandbox-banner-#{tab}")
      end

      assert html =~
               "Changes you make here only apply to this sandbox and do not sync"
    end

    test "shows Inherited banner on security tab", %{
      conn: conn,
      sandbox: sandbox
    } do
      {:ok, _view, html} = live(conn, ~p"/projects/#{sandbox.id}/settings")

      assert html =~ ~s(id="sandbox-banner-security")
      assert html =~ "These settings are inherited from the parent project"
    end

    test "shows 'Sandbox Identity' header instead of 'Project Identity'", %{
      conn: conn,
      sandbox: sandbox
    } do
      {:ok, _view, html} = live(conn, ~p"/projects/#{sandbox.id}/settings")

      assert html =~ "Sandbox Identity"
      assert html =~ "Sandbox setup"
      assert html =~ "Identifies this sandbox within its parent:"
      assert html =~ "parent-project"
    end

    test "shows the danger zone delete button", %{conn: conn, sandbox: sandbox} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{sandbox.id}/settings")

      assert html =~ "The danger zone"
      assert html =~ "Delete sandbox"
      refute html =~ "Delete project"
    end

    test "delete sandbox flow calls delete_sandbox and redirects to root project",
         %{conn: conn, sandbox: sandbox, parent: parent} do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{sandbox.id}/settings/delete")

      view
      |> form("#confirm-delete-sandbox form",
        confirm: %{name: sandbox.name}
      )
      |> render_submit()

      flash = assert_redirected(view, ~p"/projects/#{parent.id}/w")
      assert flash["info"] =~ "and all its associated descendants deleted"
      assert is_nil(Lightning.Projects.get_project(sandbox.id))
    end

    test "confirm-delete-validate marks the form invalid for a wrong name",
         %{conn: conn, sandbox: sandbox} do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{sandbox.id}/settings/delete")

      html =
        view
        |> form("#confirm-delete-sandbox form", confirm: %{name: "wrong"})
        |> render_change()

      assert html =~ "does not match the sandbox name"
      # Sandbox was not deleted
      assert Lightning.Projects.get_project(sandbox.id)
    end

    test "submitting the confirm form with a wrong name does not delete and re-renders errors",
         %{conn: conn, sandbox: sandbox} do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{sandbox.id}/settings/delete")

      html =
        view
        |> form("#confirm-delete-sandbox form", confirm: %{name: "wrong"})
        |> render_submit()

      assert html =~ "does not match the sandbox name"
      assert Lightning.Projects.get_project(sandbox.id)
    end

    test "close button navigates back to the settings index",
         %{conn: conn, sandbox: sandbox} do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{sandbox.id}/settings/delete")

      view
      |> element("#confirm-delete-sandbox button[aria-label='Close']")
      |> render_click()

      assert_redirected(view, ~p"/projects/#{sandbox.id}/settings")
    end

    test "unauthorized sandbox delete surfaces an error and returns to settings",
         %{conn: conn, sandbox: sandbox} do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{sandbox.id}/settings/delete")

      # Simulate an authorization mismatch by stubbing the sandbox delete call
      # to return :unauthorized while the settings page's own can_delete_project
      # gate allowed us through.
      Mimic.expect(Lightning.Projects.Sandboxes, :delete_sandbox, fn _, _ ->
        {:error, :unauthorized}
      end)

      view
      |> form("#confirm-delete-sandbox form",
        confirm: %{name: sandbox.name}
      )
      |> render_submit()

      flash = assert_redirected(view, ~p"/projects/#{sandbox.id}/settings")
      assert flash["error"] =~ "permission to delete this sandbox"
      assert Lightning.Projects.get_project(sandbox.id)
    end

    test "unexpected sandbox delete error surfaces a generic error",
         %{conn: conn, sandbox: sandbox} do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{sandbox.id}/settings/delete")

      Mimic.expect(Lightning.Projects.Sandboxes, :delete_sandbox, fn _, _ ->
        {:error, :boom}
      end)

      view
      |> form("#confirm-delete-sandbox form",
        confirm: %{name: sandbox.name}
      )
      |> render_submit()

      flash = assert_redirected(view, ~p"/projects/#{sandbox.id}/settings")
      assert flash["error"] =~ "Could not delete sandbox"
      assert Lightning.Projects.get_project(sandbox.id)
    end

    test "shows webhook security explanatory message instead of auth methods",
         %{conn: conn, sandbox: sandbox} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{sandbox.id}/settings")

      assert html =~ "Webhook authentication is managed in the parent project"
    end

    test "MFA toggle is disabled in sandbox", %{conn: conn, sandbox: sandbox} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{sandbox.id}/settings")
      html = render(view)

      assert html =~ ~s(id="toggle-mfa-switch")
      assert html =~ ~s(disabled)
      assert html =~ "cursor-not-allowed"
    end

    test "does not show the role permissions message on webhook_security or security tabs",
         %{conn: conn, sandbox: sandbox} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{sandbox.id}/settings")

      refute html =~ "Role based permissions: You cannot modify"
    end
  end
end
