defmodule LightningWeb.API.Session.ReadingAndSigningOutTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import Lightning.Factories

  alias Lightning.Accounts
  alias Lightning.Config.API, as: ConfigAPI

  describe "reading the session" do
    test "answers the session and a CSRF token that works for writes" do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user, role: :owner}])
      conn = session_conn(build_conn(), user, csrf: false)

      answer = get(conn, ~p"/api/session")
      body = json_response(answer, 200)

      assert body == %{
               "data" => %{
                 "state" => "signed_in",
                 "user_id" => user.id,
                 "stepped_up_until" => nil,
                 "csrf_token" => body["data"]["csrf_token"],
                 "pending_signup" => nil
               }
             }

      assert get_resp_header(answer, "cache-control") == ["no-store"]

      conn
      |> put_req_header("x-csrf-token", body["data"]["csrf_token"])
      |> post(~p"/api/projects/#{project.id}/workflows", "[1]")
      |> assert_problem(400, :malformed, [])
    end

    test "says until when the session is stepped up" do
      user = insert(:user)
      conn = build_conn() |> session_conn(user) |> step_up(user, 60)

      {:ok, until, 0} =
        conn
        |> get(~p"/api/session")
        |> json_response(200)
        |> get_in(["data", "stepped_up_until"])
        |> DateTime.from_iso8601()

      assert_in_delta DateTime.diff(until, DateTime.utc_now()), 240, 5
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

      conn = build_conn() |> session_conn(user) |> get(~p"/api/session")

      assert json_response(conn, 200)["data"]["state"] == "confirmation_required"
    end

    test "answers no session, or one from another site, with unauthenticated" do
      for conn <- [
            from_own_page(build_conn()),
            session_conn(build_conn(), insert(:user), origin: :cross)
          ] do
        conn
        |> get(~p"/api/session")
        |> assert_unauthenticated(:unauthenticated, [
          ~s(Session realm="Lightning")
        ])
      end
    end
  end

  describe "signing out" do
    test "ends the session and its step-up, and answers 204" do
      user = insert(:user)
      conn = session_conn(build_conn(), user, stepped_up: true)
      session_token = get_session(conn, :user_token)
      sudo_token = conn |> get_session(:sudo_token) |> Base.decode64!()

      answer = delete(conn, ~p"/api/session")

      assert response(answer, 204) == ""
      refute Accounts.get_user_by_session_token(session_token)
      refute Accounts.sudo_session_token_valid?(user, sudo_token)
    end

    test "answers 204 when there is no session, or it comes from another site, and ends nothing" do
      user = insert(:user)
      cross_site = session_conn(build_conn(), user, origin: :cross)

      for conn <- [from_own_page(build_conn()), cross_site] do
        assert response(delete(conn, ~p"/api/session"), 204) == ""
      end

      assert Accounts.get_user_by_session_token(
               get_session(cross_site, :user_token)
             )
    end

    test "needs the session's CSRF token, and ends nothing without it" do
      user = insert(:user)
      conn = session_conn(build_conn(), user, csrf: false)

      conn
      |> delete(~p"/api/session")
      |> assert_problem(400, :invalid_header, [
        %{
          "header" => "x-csrf-token",
          "code" => "required",
          "detail" => "can't be blank"
        }
      ])

      assert Accounts.get_user_by_session_token(get_session(conn, :user_token))
    end
  end
end
