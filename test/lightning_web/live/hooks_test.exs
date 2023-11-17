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

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      query =
        from t in Lightning.Accounts.UserToken, where: t.user_id == ^user.id

      Lightning.Repo.delete_all(query)

      result =
        view
        |> element("#workflow-card-#{workflow.id}")
        |> render_click()
        |> follow_redirect(conn)

      assert {:error, {:redirect, %{to: "/users/log_in", flash: %{}}}} = result
    end
  end
end
