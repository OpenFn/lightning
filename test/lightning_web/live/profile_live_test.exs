defmodule LightningWeb.ProfileLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.AccountsFixtures
  import Swoosh.TestAssertions

  @update_password_attrs %{
    current_password: valid_user_password(),
    password: "password1",
    password_confirmation: "password1"
  }

  @invalid_empty_password_attrs %{
    current_password: "",
    password: "",
    password_confirmation: ""
  }

  @invalid_schedule_deletion_attrs %{
    scheduled_deletion_email: "invalid@email.com"
  }

  @invalid_too_short_password_attrs %{
    current_password: "",
    password: "abc",
    password_confirmation: ""
  }

  @invalid_dont_match_password_attrs %{
    current_password: "",
    password: "password1",
    password_confirmation: "password2"
  }

  describe "Edit user profile" do
    setup :register_and_log_in_user

    test "load edit page", %{conn: conn} do
      {:ok, _profile_live, html} =
        live(conn, Routes.profile_edit_path(conn, :edit))

      assert html =~ "Change email"
      assert html =~ "Change password"
    end

    test "save password", %{conn: conn} do
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

      assert profile_live
             |> form("#password_form", user: @invalid_empty_password_attrs)
             |> render_submit() =~ "can&#39;t be blank"

      assert profile_live
             |> form("#password_form", user: @invalid_dont_match_password_attrs)
             |> render_submit() =~ "does not match password"

      assert profile_live
             |> form("#password_form", user: @invalid_too_short_password_attrs)
             |> render_submit() =~ "should be at least 8 character(s)"

      {:ok, conn} =
        profile_live
        |> form("#password_form", user: @update_password_attrs)
        |> render_submit()
        |> follow_redirect(conn)

      assert "/" = redirected_path = redirected_to(conn, 302)

      html =
        get(recycle(conn), redirected_path)
        |> html_response(200)

      assert html =~ "Password changed successfully."
      assert html =~ "Projects"
    end

    test "validate email", %{conn: conn, user: user} do
      {:ok, profile_live, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit))

      assert profile_live
             |> form("#email_form", user: %{email: user.email})
             |> render_change() =~ "did not change"
    end

    test "allows a user to schedule their own account for deletion", %{
      conn: conn,
      user: user
    } do
      {:ok, profile_live, html} =
        live(conn, Routes.profile_edit_path(conn, :edit))

      assert html =~ "Delete my account"

      {:ok, new_live, html} =
        profile_live
        |> element("a", "Delete my account")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.profile_edit_path(conn, :delete, user)
        )

      assert html =~
               "This user&#39;s account and credential data will be deleted"

      assert new_live
             |> form("#scheduled_deletion_form",
               user: @invalid_schedule_deletion_attrs
             )
             |> render_change() =~
               "This email doesn&#39;t match your current email"

      new_live
      |> form("#scheduled_deletion_form",
        user: %{
          scheduled_deletion_email: user.email
        }
      )
      |> render_submit()
      |> follow_redirect(conn, Routes.user_session_path(conn, :delete))

      assert_email_sent(subject: "Lightning Account Deletion", to: user.email)
    end

    test "user cancels deletion", %{
      conn: conn,
      user: user
    } do
      {:ok, profile_live, html} =
        live(conn, Routes.profile_edit_path(conn, :edit))

      assert html =~ "Delete my account"

      {:ok, new_live, html} =
        profile_live
        |> element("a", "Delete my account")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.profile_edit_path(conn, :delete, user)
        )

      assert html =~
               "This user&#39;s account and credential data will be deleted"

      {:ok, _new_live, html} =
        new_live
        |> element("button", "Cancel")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.profile_edit_path(conn, :edit)
        )

      assert html =~ "User Profile"
    end
  end
end
