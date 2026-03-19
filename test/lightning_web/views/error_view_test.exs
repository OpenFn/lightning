defmodule LightningWeb.ErrorViewTest do
  use LightningWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "ErrorHTML renders 404.html" do
    rendered =
      LightningWeb.ErrorHTML.render("404.html", %{}) |> rendered_to_string()

    assert rendered =~ "Not Found"
  end

  test "ErrorHTML renders fallback for unknown templates" do
    assert LightningWeb.ErrorHTML.render("500.html", %{}) ==
             "Internal Server Error"
  end

  test "ErrorJSON renders error with message" do
    assert LightningWeb.ErrorJSON.render("403.json", %{error: "Forbidden"}) ==
             %{"error" => "Forbidden"}
  end

  test "ErrorJSON renders fallback status message" do
    assert LightningWeb.ErrorJSON.render("500.json", %{}) ==
             %{"error" => "Internal Server Error"}
  end

  describe "integration" do
    test "returns 404 HTML for unknown routes", %{conn: conn} do
      conn = get(conn, "/this-path-does-not-exist")

      assert html_response(conn, 404) =~ "Not Found"
    end

    test "returns 404 JSON for unknown routes when JSON is requested", %{
      conn: conn
    } do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get("/this-path-does-not-exist")

      assert json_response(conn, 404) == %{"error" => "Not Found"}
    end
  end
end
