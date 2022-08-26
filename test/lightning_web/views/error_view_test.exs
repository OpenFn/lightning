defmodule LightningWeb.ErrorViewTest do
  use LightningWeb.ConnCase, async: true

  # Bring render/3 and render_to_string/3 for testing custom views
  import Phoenix.View

  test "renders 404.html" do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)

    rendered =
      render_to_string(LightningWeb.ErrorView, "404.html", %{
        conn: conn
      })

    assert rendered =~ "Not Found"
  end

  test "renders 500.html" do
    assert render_to_string(LightningWeb.ErrorView, "500.html", []) ==
             "Internal Server Error"
  end
end
