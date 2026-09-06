defmodule LightningWeb.HooksTest do
  use LightningWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  import Lightning.Factories

  import Ecto.Query

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "project_scope" do
    test "redirects to /users/login when current_user assign is missing", %{
      conn: conn,
      project: project,
      user: user
    } do
      workflow = insert(:workflow, project: project, name: "One")

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w", on_error: :raise)

      query =
        from t in Lightning.Accounts.UserToken, where: t.user_id == ^user.id

      Lightning.Repo.delete_all(query)

      result =
        view
        |> element("#workflow-#{workflow.id}")
        |> render_click()
        |> follow_redirect(conn)

      assert {:error, {:redirect, %{to: "/users/log_in", flash: %{}}}} = result
    end
  end

  describe "ensure_admin" do
    test "continues for a user who can access the admin space" do
      admin = insert(:user, role: :superuser)
      socket = admin_socket(admin)

      assert {:cont, ^socket} =
               LightningWeb.Hooks.on_mount(:ensure_admin, %{}, %{}, socket)
    end

    test "halts and redirects a user who cannot" do
      socket = admin_socket(insert(:user))

      assert {:halt, halted} =
               LightningWeb.Hooks.on_mount(:ensure_admin, %{}, %{}, socket)

      assert {:redirect, %{to: "/projects"}} = halted.redirected
    end

    test "halts and redirects to log in when there is no current user" do
      socket = admin_socket(nil)

      assert {:halt, halted} =
               LightningWeb.Hooks.on_mount(:ensure_admin, %{}, %{}, socket)

      assert {:redirect, %{to: "/users/log_in"}} = halted.redirected
    end

    test "a non-admin is redirected away from an admin LiveView", %{conn: conn} do
      # current_user from setup is a regular (non-superuser) user
      assert {:error, {redirect, %{to: "/projects"}}} =
               live(conn, ~p"/settings/projects")

      assert redirect in [:redirect, :live_redirect]
    end
  end

  defp admin_socket(user) do
    %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}, current_user: user},
      private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}, live_temp: %{}}
    }
  end
end
