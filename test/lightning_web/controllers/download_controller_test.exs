defmodule LightningWeb.DownloadControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  describe "GET /downloads/yaml" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    test "correctly renders a project yaml", %{conn: conn, project: project} do
      response =
        conn
        |> get(~p"/download/yaml?#{%{id: project.id}}")

      assert response.status == 200
    end

    test "redirects with the reason when two names collide", %{
      conn: conn,
      project: project
    } do
      # Both hyphenate to `My-Flow`. `workflows` is unique on the raw name, so
      # this is a state a user can reach by naming two workflows a hyphen apart.
      for name <- ["My Flow", "My-Flow"] do
        insert(:simple_workflow, name: name, project: project)
      end

      response = get(conn, ~p"/download/yaml?#{%{id: project.id}}")

      assert redirected_to(response) == ~p"/projects/#{project.id}/settings"

      assert Phoenix.Flash.get(response.assigns.flash, :error) =~
               "two workflows in this project"
    end

    test "renders a 404? when the user isn't authorized", %{conn: conn} do
      p = insert(:project)

      response =
        conn
        |> get(~p"/download/yaml?#{%{id: p.id}}")

      assert response.status == 401
    end
  end

  describe "when not logged in" do
    test "redirects when you are not logged in", %{conn: conn} do
      response =
        conn
        |> get("/download/yaml?id=#{Ecto.UUID.generate()}")

      assert response.status == 302
      assert response.resp_headers
      assert {"location", "/users/log_in"} in response.resp_headers
    end
  end
end
