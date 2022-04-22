defmodule LightningWeb.PageControllerTest do
  use LightningWeb.ConnCase, async: true

  test "GET /", %{conn: conn} do
    conn = get(conn, "/")
    assert redirected_to(conn) == "/users/log_in"
    assert html_response(conn, 302) =~ "You are being <a href=\"/users/log_in\">redirected</a>."
  end
end
