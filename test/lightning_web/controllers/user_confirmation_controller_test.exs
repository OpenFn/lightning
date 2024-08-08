defmodule LightningWeb.UserConfirmationControllerTest do
  use LightningWeb.ConnCase, async: true

  alias Lightning.Accounts
  alias Lightning.Repo
  import Lightning.AccountsFixtures
  import Lightning.Factories
  import Swoosh.TestAssertions

  setup do
    %{user: user_fixture()}
  end

  describe "GET /users/confirm" do
    test "renders the resend confirmation page", %{conn: conn} do
      conn = get(conn, Routes.user_confirmation_path(conn, :new))
      response = html_response(conn, 200)
      assert response =~ "Resend confirmation instructions"
    end
  end

  describe "GET /users/send-confirmation-email" do
    test "sends confirmation email to the logged in user when that user has not confirmed their accounts",
         %{conn: conn} do
      user = insert(:user, confirmed_at: nil)

      conn =
        conn
        |> log_in_user(user)
        |> get("/users/send-confirmation-email")

      assert redirected_to(conn) == "/projects"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Confirmation email sent successfully"

      assert_email_sent(
        subject: "Confirm your OpenFn account",
        to: user.email
      )
    end

    test "doesn't sends confirmation email to the logged in user when that user has confirmed their accounts",
         %{conn: conn} do
      user = insert(:user, confirmed_at: DateTime.utc_now())

      conn =
        conn
        |> log_in_user(user)
        |> get("/users/send-confirmation-email")

      assert redirected_to(conn) == "/projects"

      refute Phoenix.Flash.get(conn.assigns.flash, :info)

      refute_email_sent(subject: "Confirm your OpenFn account")
    end
  end

  describe "POST /users/confirm" do
    @tag :capture_log
    test "sends a new confirmation token", %{conn: conn, user: user} do
      conn =
        post(conn, Routes.user_confirmation_path(conn, :create), %{
          "user" => %{"email" => user.email}
        })

      assert redirected_to(conn) == "/projects"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"

      assert Repo.get_by!(Accounts.UserToken, user_id: user.id).context ==
               "confirm"
    end

    test "does not send confirmation token if User is confirmed", %{
      conn: conn,
      user: user
    } do
      Repo.update!(Accounts.User.confirm_changeset(user))

      conn =
        post(conn, Routes.user_confirmation_path(conn, :create), %{
          "user" => %{"email" => user.email}
        })

      assert redirected_to(conn) == "/projects"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"

      refute Repo.get_by(Accounts.UserToken, user_id: user.id)
    end

    test "does not send confirmation token if email is invalid", %{conn: conn} do
      conn =
        post(conn, Routes.user_confirmation_path(conn, :create), %{
          "user" => %{"email" => "unknown@example.com"}
        })

      assert redirected_to(conn) == "/projects"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"

      assert Repo.all(Accounts.UserToken) == []
    end
  end

  describe "GET /users/confirm/:token" do
    test "renders the confirmation page", %{conn: conn} do
      conn = get(conn, Routes.user_confirmation_path(conn, :edit, "some-token"))
      response = html_response(conn, 200)
      assert response =~ "Confirm account"

      form_action = Routes.user_confirmation_path(conn, :update, "some-token")
      assert response =~ "action=\"#{form_action}\""
    end
  end

  describe "POST /users/confirm/:token" do
    test "confirms the given token once", %{conn: conn, user: user} do
      {encoded_token, user_token} =
        Accounts.UserToken.build_email_token(user, "confirm", user.email)

      Repo.insert!(user_token)

      conn =
        post(conn, Routes.user_confirmation_path(conn, :update, encoded_token))

      assert redirected_to(conn) == "/projects"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "User confirmed successfully"

      assert Accounts.get_user!(user.id).confirmed_at
      refute get_session(conn, :user_token)
      assert Repo.all(Accounts.UserToken) == []

      # When not logged in
      conn =
        post(conn, Routes.user_confirmation_path(conn, :update, encoded_token))

      assert redirected_to(conn) == "/projects"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "User confirmation link is invalid or it has expired"

      # When logged in
      conn =
        build_conn()
        |> log_in_user(user)
        |> post(Routes.user_confirmation_path(conn, :update, encoded_token))

      assert redirected_to(conn) == "/projects"
      refute Phoenix.Flash.get(conn.assigns.flash, :error)
    end

    test "does not confirm email with invalid token", %{conn: conn, user: user} do
      conn = post(conn, Routes.user_confirmation_path(conn, :update, "oops"))
      assert redirected_to(conn) == "/projects"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "User confirmation link is invalid or it has expired"

      refute Accounts.get_user!(user.id).confirmed_at
    end
  end

  describe "GET /profile/confirm_email/:token" do
    setup %{user: user} do
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_update_email_instructions(
            user,
            "#{email}",
            url
          )
        end)

      %{token: token, email: email}
    end

    test "updates the user email once", %{
      conn: conn,
      user: user,
      token: token,
      email: email
    } do
      conn =
        get(
          conn |> log_in_user(user),
          Routes.user_confirmation_path(conn, :confirm_email, token)
        )

      assert redirected_to(conn) == "/projects"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Email changed successfully."

      assert Accounts.get_user!(user.id).confirmed_at
      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      conn =
        get(conn, Routes.user_confirmation_path(conn, :confirm_email, token))

      assert redirected_to(conn) == "/projects"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Email change link is invalid or it has expired."
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      conn =
        get(
          conn |> log_in_user(user),
          Routes.user_confirmation_path(
            conn,
            :confirm_email,
            "oops"
          )
        )

      assert redirected_to(conn) == "/projects"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Email change link is invalid or it has expired"

      refute Accounts.get_user!(user.id).confirmed_at
      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()

      conn =
        get(conn, Routes.user_confirmation_path(conn, :confirm_email, token))

      assert redirected_to(conn) == Routes.user_session_path(conn, :new)
    end
  end
end
