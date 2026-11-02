defmodule LightningWeb.API.PasswordResetsTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.AccountsFixtures
  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import Swoosh.TestAssertions

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Accounts.UserToken
  alias Lightning.Repo

  defp json_conn do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
  end

  defp reset_token(user) do
    extract_user_token(fn url ->
      Accounts.deliver_user_reset_password_instructions(user, url)
    end)
  end

  describe "requesting a reset" do
    test "emails the account a link to the reset page and answers 202 with no body" do
      user = insert(:user)

      conn =
        post(json_conn(), ~p"/api/password_resets", %{"email" => user.email})

      assert conn.status == 202
      assert conn.resp_body == ""

      assert_email_sent(fn email ->
        assert [{_name, to}] = email.to
        assert to == user.email

        assert email.text_body =~
                 LightningWeb.Endpoint.url() <> "/users/reset_password/"
      end)

      assert [%UserToken{context: "reset_password"}] =
               Repo.all(UserToken)
    end

    test "answers an email no account has the same way, and sends nothing" do
      conn =
        post(json_conn(), ~p"/api/password_resets", %{
          "email" => "nobody@example.com"
        })

      assert conn.status == 202
      assert conn.resp_body == ""
      assert_no_email_sent()
      assert Repo.all(UserToken) == []
    end

    test "works from a signed-in session too" do
      user = insert(:user)

      conn =
        build_conn()
        |> session_conn(user)
        |> post(~p"/api/password_resets", %{"email" => user.email})

      assert conn.status == 202
      assert_email_sent(fn email -> assert [{_name, _to}] = email.to end)
    end

    test "refuses a body that isn't an object with malformed" do
      json_conn()
      |> post(~p"/api/password_resets", "[1]")
      |> assert_problem(400, :malformed, [])
    end

    test "refuses a missing or mistyped email, and any other key, with invalid" do
      for {body, entries} <- [
            {%{},
             [
               %{
                 "pointer" => "#/email",
                 "code" => "required",
                 "detail" => "can't be blank"
               }
             ]},
            {%{"email" => 7, "name" => "Ada"},
             [
               %{
                 "pointer" => "#/email",
                 "code" => "type",
                 "detail" => "is invalid"
               },
               %{
                 "pointer" => "#/name",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               }
             ]}
          ] do
        json_conn()
        |> post(~p"/api/password_resets", body)
        |> assert_problem(422, :invalid, entries)
      end

      assert_no_email_sent()
    end
  end

  describe "resetting a password" do
    test "sets the password, revokes every token, signs no one in, and answers 204" do
      user = insert(:user)
      api_token = Accounts.generate_api_token(user)
      session_token = Accounts.generate_user_session_token(user)
      token = reset_token(user)

      conn =
        put(json_conn(), ~p"/api/password_resets/#{token}", %{
          "password" => "a brand new password"
        })

      assert conn.status == 204
      assert conn.resp_body == ""
      assert get_resp_cookies(conn) == %{}

      assert %User{} =
               Accounts.get_user_by_email_and_password(
                 user.email,
                 "a brand new password"
               )

      refute Accounts.get_user_by_api_token(api_token)
      refute Accounts.get_user_by_session_token(session_token)
      assert Repo.all(UserToken) == []
    end

    test "answers a used, expired or unknown token with not_found" do
      user = insert(:user)
      used = reset_token(user)

      {:ok, _user} =
        Accounts.reset_user_password(
          Accounts.get_user_by_reset_password_token(used),
          %{"password" => "a brand new password"}
        )

      expired = reset_token(user)

      Repo.update_all(UserToken,
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -2, :day)]
      )

      for token <- [used, expired, "not-a-token"] do
        json_conn()
        |> put(~p"/api/password_resets/#{token}", %{
          "password" => "another new password"
        })
        |> assert_problem(404, :not_found, [])
      end

      refute Accounts.get_user_by_email_and_password(
               user.email,
               "another new password"
             )
    end

    test "answers an unknown token with not_found before reading the body" do
      json_conn()
      |> put(~p"/api/password_resets/not-a-token", "[1]")
      |> assert_problem(404, :not_found, [])
    end

    test "refuses a body that isn't an object with malformed" do
      token = reset_token(insert(:user))

      json_conn()
      |> put(~p"/api/password_resets/#{token}", "[1]")
      |> assert_problem(400, :malformed, [])
    end

    test "refuses a short, long or missing password, and any other key, and keeps the token" do
      user = insert(:user)
      token = reset_token(user)

      for {body, entries} <- [
            {%{"password" => "short"},
             [
               %{
                 "pointer" => "#/password",
                 "code" => "too_short",
                 "detail" => "should be at least 12 character(s)"
               }
             ]},
            {%{"password" => String.duplicate("a", 73)},
             [
               %{
                 "pointer" => "#/password",
                 "code" => "too_long",
                 "detail" => "should be at most 72 character(s)"
               }
             ]},
            {%{"password_confirmation" => "x"},
             [
               %{
                 "pointer" => "#/password",
                 "code" => "required",
                 "detail" => "can't be blank"
               },
               %{
                 "pointer" => "#/password_confirmation",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               }
             ]}
          ] do
        json_conn()
        |> put(~p"/api/password_resets/#{token}", body)
        |> assert_problem(422, :invalid, entries)
      end

      assert Accounts.get_user_by_reset_password_token(token)
    end
  end
end
