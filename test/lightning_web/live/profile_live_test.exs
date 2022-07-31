defmodule LightningWeb.ProfileLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "Edit user profile" do
    setup :register_and_log_in_superuser

    test "load edit page", %{conn: conn, user: user} do
      {:ok, _profile_live, html} =
        live(conn, Routes.profile_edit_path(conn, :edit))
    end
  end
end
