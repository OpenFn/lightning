defmodule LightningWeb.API.Session.SigningInTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import Lightning.Factories

  alias Lightning.Accounts
  alias Lightning.Config.API, as: ConfigAPI

  @password "hello world!"
  @session_challenge [~s(Session realm="Lightning")]

  defp mfa_user do
    insert(:user,
      mfa_enabled: true,
      user_totp: build(:user_totp),
      backup_codes: build_list(10, :backup_code)
    )
  end

  defp totp(user), do: NimbleTOTP.verification_code(user.user_totp.secret)

  defp sign_in(conn, body),
    do: post(conn, ~p"/api/session", Jason.encode!(body))

  # The next request from the same browser: the cookie the answer set, from
  # Lightning's own page, with the CSRF token the answer gave.
  defp next_request(conn) do
    csrf_token = json_response(conn, 201)["data"]["csrf_token"]

    conn
    |> recycle()
    |> from_own_page()
    |> put_req_header("x-csrf-token", csrf_token)
  end

  defp assert_signed_in(conn, user, stepped_up_until \\ nil) do
    body = json_response(conn, 201)

    assert body == %{
             "data" => %{
               "state" => "signed_in",
               "user_id" => user.id,
               "stepped_up_until" => stepped_up_until,
               "csrf_token" => body["data"]["csrf_token"],
               "pending_signup" => nil
             }
           }

    assert is_binary(body["data"]["csrf_token"])
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  defp assert_invalid_credentials(conn),
    do: assert_unauthenticated(conn, :invalid_credentials, @session_challenge)

  describe "signing in with a password" do
    test "answers 201 with the session, whose cookie and CSRF token then work on the API" do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user, role: :owner}])

      conn =
        build_conn()
        |> from_own_page()
        |> sign_in(%{email: user.email, password: @password})

      assert_signed_in(conn, user)

      next = next_request(conn)

      assert json_response(get(next, ~p"/api/projects/#{project.id}"), 200)[
               "data"
             ]["id"] == project.id

      next
      |> post(~p"/api/projects/#{project.id}/workflows", "[1]")
      |> assert_problem(400, :malformed, [])
    end

    test "answers an account past its confirmation deadline with its state" do
      Mox.stub(Lightning.MockConfig, :check_flag?, fn
        :require_email_verification -> true
        flag -> ConfigAPI.check_flag?(flag)
      end)

      user =
        insert(:user,
          confirmed_at: nil,
          inserted_at: DateTime.add(DateTime.utc_now(), -49, :hour)
        )

      conn =
        build_conn()
        |> from_own_page()
        |> sign_in(%{email: user.email, password: @password})

      assert json_response(conn, 201)["data"]["state"] ==
               "confirmation_required"
    end

    test "refuses every failed sign-in alike, and sets no session" do
      user = insert(:user)
      disabled = insert(:user, disabled: true)

      scheduled =
        insert(:user,
          scheduled_deletion: DateTime.add(DateTime.utc_now(), 7, :day)
        )

      for body <- [
            %{email: "nobody@example.com", password: @password},
            %{email: user.email, password: "not the password"},
            %{email: String.upcase(user.email), password: "not the password"},
            %{email: disabled.email, password: @password},
            %{email: scheduled.email, password: @password},
            %{email: user.email, password: ""}
          ] do
        conn = build_conn() |> from_own_page() |> sign_in(body)

        assert_invalid_credentials(conn)
        assert get_resp_header(conn, "set-cookie") == []
      end
    end

    test "refuses a request from another site, so it can't sign a browser in" do
      user = insert(:user)

      for conn <- [
            put_req_header(
              from_own_page(build_conn()),
              "sec-fetch-site",
              "cross-site"
            ),
            build_conn()
            |> put_req_header("content-type", "application/json")
            |> put_req_header("accept", "application/json")
          ] do
        conn = sign_in(conn, %{email: user.email, password: @password})

        assert_problem(conn, 403, :forbidden, [])
        assert get_resp_header(conn, "set-cookie") == []
      end
    end
  end

  describe "signing in to an account with MFA" do
    test "without a code answers mfa_required and a session that waits for one" do
      user = mfa_user()

      conn =
        build_conn()
        |> from_own_page()
        |> sign_in(%{email: user.email, password: @password})

      assert_unauthenticated(conn, :mfa_required, @session_challenge)

      next = conn |> recycle() |> from_own_page()

      assert json_response(get(next, ~p"/api/session"), 200)["data"]["state"] ==
               "mfa_required"

      next
      |> get(~p"/api/projects")
      |> assert_unauthenticated(:unauthenticated, ["Bearer"])
    end

    test "with the password and a code in one request signs in" do
      user = mfa_user()

      conn =
        build_conn()
        |> from_own_page()
        |> sign_in(%{
          email: user.email,
          password: @password,
          mfa_code: totp(user)
        })

      assert_signed_in(conn, user)
    end

    test "finishes signing in with an MFA code or a backup code, which is used up" do
      user = mfa_user()
      [backup | _rest] = user.backup_codes

      for body <- [%{mfa_code: totp(user)}, %{backup_code: backup.code}] do
        conn =
          build_conn()
          |> session_conn(user, mfa_pending: true)
          |> sign_in(body)

        assert_signed_in(conn, user)
      end

      assert Enum.find(
               Accounts.list_user_backup_codes(user),
               &(&1.id == backup.id)
             ).used_at
    end

    test "refuses a wrong code alike, with or without the password, and keeps waiting for one" do
      user = mfa_user()
      [backup | _rest] = user.backup_codes
      Accounts.valid_user_backup_code?(user, backup.code)

      for body <- [
            %{mfa_code: "000000"},
            %{backup_code: "NOTACODE1"},
            %{backup_code: backup.code}
          ] do
        conn = session_conn(build_conn(), user, mfa_pending: true)

        conn |> sign_in(body) |> assert_invalid_credentials()

        assert json_response(get(conn, ~p"/api/session"), 200)["data"]["state"] ==
                 "mfa_required"
      end

      build_conn()
      |> from_own_page()
      |> sign_in(%{email: user.email, password: @password, mfa_code: "000000"})
      |> assert_invalid_credentials()
    end

    test "with the code needs the session's CSRF token" do
      user = mfa_user()

      build_conn()
      |> session_conn(user, mfa_pending: true, csrf: false)
      |> sign_in(%{mfa_code: totp(user)})
      |> assert_problem(400, :invalid_header, [
        %{
          "header" => "x-csrf-token",
          "code" => "required",
          "detail" => "can't be blank"
        }
      ])
    end
  end

  describe "stepping up" do
    test "with the password steps the session up for five minutes" do
      user = insert(:user)

      conn =
        build_conn()
        |> session_conn(user)
        |> sign_in(%{password: @password})

      until = json_response(conn, 201)["data"]["stepped_up_until"]
      assert_signed_in(conn, user, until)

      {:ok, until, 0} = DateTime.from_iso8601(until)
      assert_in_delta DateTime.diff(until, DateTime.utc_now()), 300, 5
    end

    test "with an MFA code steps the session up" do
      user = mfa_user()

      conn =
        build_conn() |> session_conn(user) |> sign_in(%{mfa_code: totp(user)})

      assert json_response(conn, 201)["data"]["stepped_up_until"]
    end

    test "refuses a wrong password or code alike, and leaves the session as it was" do
      user = insert(:user)

      for body <- [%{password: "not the password"}, %{mfa_code: "123456"}] do
        conn = session_conn(build_conn(), user)

        conn |> sign_in(body) |> assert_invalid_credentials()

        assert json_response(get(conn, ~p"/api/session"), 200)["data"][
                 "stepped_up_until"
               ] == nil
      end
    end

    test "needs the session's CSRF token" do
      build_conn()
      |> session_conn(insert(:user), csrf: false)
      |> sign_in(%{password: @password})
      |> assert_problem(400, :invalid_header, [
        %{
          "header" => "x-csrf-token",
          "code" => "required",
          "detail" => "can't be blank"
        }
      ])
    end

    test "takes the password or an MFA code, and not a backup code" do
      user = mfa_user()
      [backup | _rest] = user.backup_codes

      for {body, entries} <- [
            {%{},
             [
               %{
                 "pointer" => "#/password",
                 "code" => "required",
                 "detail" => "can't be blank"
               }
             ]},
            {%{backup_code: backup.code},
             [
               %{
                 "pointer" => "#/backup_code",
                 "code" => "not_allowed",
                 "detail" => "can't be used to step up"
               }
             ]},
            {%{password: @password, mfa_code: "123456"},
             [
               %{
                 "pointer" => "#/mfa_code",
                 "code" => "exclusive",
                 "detail" => "can't be sent with password"
               }
             ]}
          ] do
        build_conn()
        |> session_conn(user)
        |> sign_in(body)
        |> assert_problem(422, :invalid, entries)
      end

      assert is_nil(
               Enum.find(
                 Accounts.list_user_backup_codes(user),
                 &(&1.id == backup.id)
               ).used_at
             )
    end
  end

  describe "continuing a session without one" do
    test "is unauthenticated, whether there never was one or it has ended" do
      user = mfa_user()
      ended = session_conn(build_conn(), user, mfa_pending: true)
      Accounts.delete_session_token(get_session(ended, :user_token))

      for conn <- [from_own_page(build_conn()), ended],
          body <- [
            %{password: @password},
            %{mfa_code: totp(user)},
            %{backup_code: "NOTACODE1"}
          ] do
        conn
        |> sign_in(body)
        |> assert_unauthenticated(:unauthenticated, @session_challenge)
      end
    end
  end

  describe "a body that isn't valid" do
    test "that isn't an object is malformed" do
      build_conn()
      |> from_own_page()
      |> post(~p"/api/session", "[1]")
      |> assert_problem(400, :malformed, [])
    end

    test "reports every problem together" do
      for {body, entries} <- [
            {%{email: "a@example.com"},
             [
               %{
                 "pointer" => "#/password",
                 "code" => "required",
                 "detail" => "can't be blank"
               }
             ]},
            {%{email: 1, password: ["x"], remember_me: true},
             [
               %{
                 "pointer" => "#/email",
                 "code" => "type",
                 "detail" => "is invalid"
               },
               %{
                 "pointer" => "#/password",
                 "code" => "type",
                 "detail" => "is invalid"
               },
               %{
                 "pointer" => "#/remember_me",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               }
             ]},
            {%{
               email: "a@example.com",
               password: "x",
               mfa_code: "1",
               backup_code: "2"
             },
             [
               %{
                 "pointer" => "#/backup_code",
                 "code" => "exclusive",
                 "detail" => "can't be sent with mfa_code"
               }
             ]}
          ] do
        build_conn()
        |> from_own_page()
        |> sign_in(body)
        |> assert_problem(422, :invalid, entries)
      end
    end
  end
end
