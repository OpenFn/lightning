defmodule LightningWeb.VersionControlControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  describe "GET setup_vcs" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    test "redirects to project setting on a good installation", %{
      conn: conn,
      project: project,
      user: user
    } do
      p_repo =
        insert(:project_repo, %{
          github_installation_id: nil,
          branch: nil,
          repo: nil,
          user: user,
          user_id: user.id,
          project: project,
          project_id: project.id
        })

      response =
        conn
        |> get(~p"/setup_vcs?installation_id=some_id")

      assert response.status == 302

      assert redirected_to(response) ==
               ~p"/projects/#{p_repo.project_id}/settings#vcs"
    end
  end

  describe "when not logged in" do
    test "redirects when you are not logged in", %{conn: conn} do
      response =
        conn
        |> get("/setup_vcs")

      assert response.status == 302
      assert response.resp_headers
      assert {"location", "/users/log_in"} in response.resp_headers
    end
  end
end
