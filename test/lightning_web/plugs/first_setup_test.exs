defmodule LightningWeb.Plugs.FirstSetupTest do
  use LightningWeb.ConnCase, async: true
  alias LightningWeb.Plugs.FirstSetup

  @tag create_initial_user: false
  test "redirects when there is no first user", %{conn: conn} do
    conn = conn |> FirstSetup.call(%{}) |> get("/")

    assert redirected_to(conn) == "/first_setup"
  end

  test "redirects to /projects when there is a first user", context do
    %{conn: conn} = register_and_log_in_user(context)
    conn = conn |> FirstSetup.call(%{}) |> get("/")

    assert conn.request_path == "/"
    assert conn.status == 302
  end
end
