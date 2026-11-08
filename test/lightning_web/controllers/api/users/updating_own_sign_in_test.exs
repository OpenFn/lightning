defmodule LightningWeb.API.Users.UpdatingOwnSignInTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiUsersHelpers, only: [password: 0, watch_sockets: 1]
  import Lightning.Factories
  import Swoosh.TestAssertions

  alias Lightning.Accounts
  alias Lightning.Accounts.User

  setup do
    %{user: insert(:user, email: "ada@example.com", first_name: "Ada")}
  end

  defp stepped_up(user), do: session_conn(build_conn(), user, stepped_up: true)

  describe "a person changing their own password or email" do
    test "is refused on a personal access token with 403 forbidden, and on a session that hasn't stepped up with step_up_required, changing nothing",
         %{user: user} do
      personal =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> assign_bearer(Accounts.generate_api_token(user))

      for {caller, status_code} <- [
            {personal, :forbidden},
            {session_conn(build_conn(), user), :step_up_required}
          ],
          body <- [
            %{password: password()},
            %{email: "grace@example.com"},
            %{first_name: "Grace", password: password()}
          ] do
        caller
        |> patch(~p"/api/users/#{user.id}", body)
        |> assert_problem(403, status_code, [])
      end

      assert %User{first_name: "Ada", email: "ada@example.com"} =
               Accounts.get_user(user.id)

      assert Accounts.get_user_by_email_and_password(user.email, "hello world!")
      refute Accounts.pending_email(user)
      assert_no_email_sent()
    end

    test "a new password answers 200, keeps this session, ends the others and revokes their personal access tokens",
         %{user: user} do
      conn = stepped_up(user)
      this_session = get_session(conn, :user_token)
      other_session = Accounts.generate_user_session_token(user)
      api_token = Accounts.generate_api_token(user)
      watch_sockets(user)

      assert %{"data" => %{"id" => id}} =
               conn
               |> patch(~p"/api/users/#{user.id}", %{password: password()})
               |> json_response(200)

      assert id == user.id
      assert Accounts.get_user_by_email_and_password(user.email, password())
      assert Accounts.get_user_by_session_token(this_session)
      refute Accounts.get_user_by_session_token(other_session)
      refute Accounts.get_user_by_api_token(api_token)
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}

      assert %{entries: [audit]} = Lightning.Auditing.list_all()

      assert %{
               event: "updated",
               actor_type: :user,
               metadata: %{"password_changed" => true}
             } = audit

      assert audit.actor_id == user.id
      refute inspect(audit) =~ password()
    end

    test "the password they already have changes nothing and signs no one out",
         %{user: user} do
      other_session = Accounts.generate_user_session_token(user)

      assert user
             |> stepped_up()
             |> patch(~p"/api/users/#{user.id}", %{password: "hello world!"})
             |> json_response(200)

      assert Accounts.get_user_by_session_token(other_session)
      assert %{entries: []} = Lightning.Auditing.list_all()
    end

    test "a new email answers 200 with the email unchanged, holds the new one as pending and sends a link to it, telling the old address",
         %{user: user} do
      conn =
        user
        |> stepped_up()
        |> patch(~p"/api/users/#{user.id}", %{
          email: "grace@example.com",
          first_name: "Grace"
        })

      assert %{
               "attributes" => %{
                 "email" => "ada@example.com",
                 "first_name" => "Grace"
               }
             } = json_response(conn, 200)["data"]

      assert %User{email: "ada@example.com"} = Accounts.get_user(user.id)
      assert Accounts.pending_email(user) == "grace@example.com"

      assert_email_sent(fn email ->
        assert [{_name, "ada@example.com"}] = email.to
      end)

      assert_email_sent(fn email ->
        assert [{_name, "grace@example.com"}] = email.to
      end)
    end

    test "answers 422 for an email that is the same, taken, malformed or blank, and a password too short, changing nothing",
         %{user: user} do
      insert(:user, email: "taken@example.com")

      for {body, entries} <- [
            {%{email: "ada@example.com"},
             [
               %{
                 "pointer" => "#/email",
                 "code" => "unchanged",
                 "detail" => "did not change"
               }
             ]},
            {%{email: "taken@example.com"},
             [
               %{
                 "pointer" => "#/email",
                 "code" => "taken",
                 "detail" => "has already been taken"
               }
             ]},
            {%{email: ""},
             [
               %{
                 "pointer" => "#/email",
                 "code" => "required",
                 "detail" => "can't be blank"
               }
             ]},
            {%{password: "short"},
             [
               %{
                 "pointer" => "#/password",
                 "code" => "too_short",
                 "detail" => "should be at least 12 character(s)"
               }
             ]}
          ] do
        user
        |> stepped_up()
        |> patch(~p"/api/users/#{user.id}", body)
        |> assert_problem(422, :invalid, entries)
      end

      conn =
        user
        |> stepped_up()
        |> patch(~p"/api/users/#{user.id}", %{email: "not an email"})

      assert [%{"pointer" => "#/email", "code" => "format"}] =
               assert_problem(conn, 422, :invalid)["errors"]

      assert Accounts.get_user_by_email_and_password(user.email, "hello world!")
      refute Accounts.pending_email(user)
      assert_no_email_sent()
    end
  end
end
