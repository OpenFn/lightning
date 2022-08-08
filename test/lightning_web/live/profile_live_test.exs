defmodule LightningWeb.ProfileLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.AccountsFixtures

  @update_password_attrs %{
    current_password: "some current password",
    password: "some new password",
    password_confirmation: "some new password"
  }

  @invalid_empty_password_attrs %{
    current_password: "",
    password: "",
    password_confirmation: ""
  }

  @invalid_too_short_password_attrs %{
    current_password: "",
    password: "abc",
    password_confirmation: ""
  }

  @invalid_dont_match_password_attrs %{
    current_password: valid_user_password(),
    password: "password1",
    password_confirmation: "password2"
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
      {:ok, profile_live, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit))

      assert profile_live
             |> form("#password_form", user: @invalid_empty_password_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert profile_live
             |> form("#password_form", user: @invalid_dont_match_password_attrs)
             |> render_change() =~ "does not match password"

      assert profile_live
             |> form("#password_form", user: @invalid_too_short_password_attrs)
             |> render_change() =~ "should be at least 8 character(s)"

      {:ok, view, html} =
        profile_live
        |> form("#password_form", user: @update_password_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.user_session_path(conn, :new))

        assert_redirected profile_live, Routes.user_session_path(conn, :new)
    end
  end
end
