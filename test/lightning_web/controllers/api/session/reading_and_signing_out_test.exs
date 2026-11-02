defmodule LightningWeb.API.Session.ReadingAndSigningOutTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import Lightning.Factories

  alias Lightning.Accounts
  alias Lightning.Accounts.UserToken
  alias Lightning.Config.API, as: ConfigAPI
  alias Lightning.Repo
  alias LightningWeb.UserAuth

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
    test "ends the session and its step-up, hangs up the person's sockets, and answers 204" do
      user = insert(:user)
      conn = session_conn(build_conn(), user, stepped_up: true)
      session_token = get_session(conn, :user_token)
      sudo_token = conn |> get_session(:sudo_token) |> Base.decode64!()
      sockets = UserAuth.user_socket_topic(user)
      LightningWeb.Endpoint.subscribe(sockets)

      answer = delete(conn, ~p"/api/session")

      assert response(answer, 204) == ""
      refute Accounts.get_user_by_session_token(session_token)
      refute Accounts.sudo_session_token_valid?(user, sudo_token)

      assert_receive %Phoenix.Socket.Broadcast{
        topic: ^sockets,
        event: "disconnect"
      }
    end

    test "ends a session whose account may no longer sign in, so it stays ended if the account is let back" do
      user = insert(:user)
      conn = session_conn(build_conn(), user, stepped_up: true)
      sudo_token = conn |> get_session(:sudo_token) |> Base.decode64!()
      # Disabled without revoking its sessions, so only signing out ends it.
      Repo.update!(Ecto.Changeset.change(user, disabled: true))

      answer = delete(conn, ~p"/api/session")

      assert response(answer, 204) == ""

      assert %{max_age: 0} =
               answer.resp_cookies["_lightning_web_user_remember_me"]

      refute Accounts.sudo_session_token_valid?(user, sudo_token)

      Repo.update!(Ecto.Changeset.change(user, disabled: false))
      conn |> get(~p"/api/session") |> assert_session_refused()
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

    test "needs the session's CSRF token, even once its account may no longer sign in, and ends nothing without it" do
      live = insert(:user)
      disabled = insert(:user)

      conns =
        [live, disabled]
        |> Enum.map(&session_conn(build_conn(), &1, csrf: false))

      Repo.update!(Ecto.Changeset.change(disabled, disabled: true))

      for conn <- conns do
        conn
        |> delete(~p"/api/session")
        |> assert_problem(400, :invalid_header, [
          %{
            "header" => "x-csrf-token",
            "code" => "required",
            "detail" => "can't be blank"
          }
        ])

        assert Repo.exists?(
                 UserToken.token_and_context_query(
                   get_session(conn, :user_token),
                   "session"
                 )
               )
      end
    end
  end
end
