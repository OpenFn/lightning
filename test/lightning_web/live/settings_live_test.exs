defmodule LightningWeb.SettingsLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "Index for superuser" do
    setup :register_and_log_in_superuser

    test "a regular user cannot access the settings page", %{
      conn: conn,
      user: _user
    } do
      {:ok, _index_live, html} =
        live(conn, Routes.settings_index_path(conn, :index))

      assert html =~ "Users"
      assert html =~ "Back"
    end
  end

  describe "Index for user" do
    setup :register_and_log_in_user

    test "a regular user cannot access the settings page", %{
      conn: conn,
      user: _user
    } do
      {:ok, _index_live, html} =
        live(conn, Routes.settings_index_path(conn, :index))
        |> follow_redirect(conn, "/")

      assert html =~ "You can&#39;t access that page"
    end
  end
end
