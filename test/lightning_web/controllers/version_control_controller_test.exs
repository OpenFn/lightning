defmodule LightningWeb.VersionControlControllerTest do
  use LightningWeb.ConnCase, async: true

  describe "GET setup_vcs" do
    setup :register_and_log_in_user

    test "responds with a html to close the page",
         %{
           conn: conn
         } do
      conn =
        get(
          conn,
          ~p"/setup_vcs?installation_id=123&setup_action=update"
        )

      assert html_response(conn, 200) =~ "window.close()"
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
