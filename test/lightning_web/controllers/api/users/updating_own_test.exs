defmodule LightningWeb.API.Users.UpdatingOwnTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiUsersHelpers, only: [user_url: 1, watch_sockets: 1]
  import Lightning.Factories

  alias Lightning.Accounts
  alias Lightning.Accounts.User

  setup do
    user =
      insert(:user,
        email: "ada@example.com",
        first_name: "Ada",
        last_name: "Lovelace",
        contact_preference: :critical
      )

    %{user: user}
  end

  defp personal_token(user) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> assign_bearer(Accounts.generate_api_token(user))
  end

  describe "a person updating their own account" do
    test "changes their names and contact preference on either token, answers 200 with the user and keeps them signed in",
         %{user: user} do
      session = Accounts.generate_user_session_token(user)
      watch_sockets(user)

      for {caller, first_name} <- [
            {personal_token(user), "Grace"},
            {session_conn(build_conn(), user), "Augusta"}
          ] do
        conn =
          patch(caller, ~p"/api/users/#{user.id}", %{
            first_name: first_name,
            last_name: "Hopper",
            contact_preference: "any"
          })

        assert json_response(conn, 200) == %{
                 "data" => %{
                   "type" => "users",
                   "id" => user.id,
                   "attributes" => %{
                     "email" => "ada@example.com",
                     "first_name" => first_name,
                     "last_name" => "Hopper",
                     "role" => "user"
                   },
                   "links" => %{"self" => user_url(user.id)}
                 }
               }

        assert %User{
                 first_name: ^first_name,
                 last_name: "Hopper",
                 contact_preference: :any
               } = Accounts.get_user(user.id)
      end

      assert Accounts.get_user_by_session_token(session)
      refute_received %Phoenix.Socket.Broadcast{event: "disconnect"}
    end

    test "records the change with the person as the actor", %{user: user} do
      assert user
             |> personal_token()
             |> patch(~p"/api/users/#{user.id}", %{first_name: "Grace"})
             |> json_response(200)

      assert %{entries: [audit]} = Lightning.Auditing.list_all()

      assert %{
               item_type: "user",
               event: "updated",
               actor_type: :user
             } = audit

      assert audit.item_id == user.id
      assert audit.actor_id == user.id
      assert audit.changes.before == %{"first_name" => "Ada"}
      assert audit.changes.after == %{"first_name" => "Grace"}
    end

    test "refuses any other key, their role included, with the body's other errors, changing nothing",
         %{user: user} do
      unknown = fn key ->
        %{
          "pointer" => "#/" <> key,
          "code" => "unknown_key",
          "detail" => "is not accepted"
        }
      end

      for {body, entries} <- [
            {%{role: "superuser"}, [unknown.("role")]},
            {%{confirmed: true, first_name: " ", contact_preference: "often"},
             [
               unknown.("confirmed"),
               %{
                 "pointer" => "#/first_name",
                 "code" => "required",
                 "detail" => "can't be blank"
               },
               %{
                 "pointer" => "#/contact_preference",
                 "code" => "not_allowed",
                 "detail" => "is invalid"
               }
             ]}
          ] do
        user
        |> personal_token()
        |> patch(~p"/api/users/#{user.id}", body)
        |> assert_problem(422, :invalid, entries)
      end

      assert %User{
               first_name: "Ada",
               email: "ada@example.com",
               role: :user,
               contact_preference: :critical
             } = Accounts.get_user(user.id)

      assert Accounts.get_user_by_email_and_password(user.email, "hello world!")
      assert %{entries: []} = Lightning.Auditing.list_all()
    end

    test "a superuser changing their own names keeps their role" do
      superuser = insert(:user, role: :superuser, first_name: "Ada")

      conn =
        superuser
        |> personal_token()
        |> patch(~p"/api/users/#{superuser.id}", %{first_name: "Grace"})

      assert %{
               "attributes" => %{"first_name" => "Grace", "role" => "superuser"}
             } = json_response(conn, 200)["data"]
    end
  end
end
