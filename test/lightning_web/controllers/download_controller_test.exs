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
