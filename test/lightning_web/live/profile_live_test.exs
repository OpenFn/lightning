defmodule LightningWeb.ProfileLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @update_password_attrs %{
    current_password: "some current password",
    password: "some new password",
    password_confirmation: "some new password"
  }

  describe "Edit user profile" do
    setup :register_and_log_in_superuser

    test "load edit page", %{conn: conn, user: user} do
      {:ok, _profile_live, html} =
        live(conn, Routes.profile_edit_path(conn, :edit))

      assert html =~ "Change email"
      assert html =~ "Change password"
    end

    test "save password", %{conn: conn, user: user} do
      {:ok, profile_live, html} =
        live(conn, Routes.profile_edit_path(conn, :edit))

      {:ok, _, html} =
        profile_live
        |> form("#job-form", job: @invalid_attrs)
        |> render_change() =~
          "can&#39;t be blank"
          # |> form("#update_password", password_changeset: @update_password_attrs)
          # |> render_submit()
          # |> follow_redirect(conn, Routes.profile_edit_path(conn, :edit))
    end
  end
end
