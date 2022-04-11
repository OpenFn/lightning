defmodule LightningWeb.Plugs.FirstSetupTest do
  use LightningWeb.ConnCase
  alias LightningWeb.Plugs.FirstSetup

  @tag create_initial_user: false
  test "redirects when there is no first user" do
    conn = build_conn() |> FirstSetup.call(%{}) |> get("/")

    assert redirected_to(conn) == "/first_setup"
  end

  test "doesn't redirect when there is a first user" do
    conn = build_conn() |> FirstSetup.call(%{}) |> get("/")

    assert conn.request_path == "/"
    assert conn.status != 302
  end
end
