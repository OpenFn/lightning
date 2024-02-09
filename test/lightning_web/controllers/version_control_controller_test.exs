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
        insert(:project_repo_connection, %{
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

    test "responds with a text when the setup_action is set to update and there's no pending installation",
         %{
           conn: conn,
           project: project,
           user: user
         } do
      installation_id = "my_id"

      insert(:project_repo_connection, %{
        github_installation_id: installation_id,
        branch: nil,
        repo: nil,
        user: user,
        project: project
      })

      conn =
        get(
          conn,
          ~p"/setup_vcs?installation_id=#{installation_id}&setup_action=update"
        )

      assert text_response(conn, 200) ==
               "GitHub installation updated successfully; you may close this page or navigate to any OpenFn project which uses this installation: #{installation_id}"
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
