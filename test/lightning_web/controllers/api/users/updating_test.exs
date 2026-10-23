defmodule LightningWeb.API.UsersUpdatingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import Lightning.RaceHelpers
  import Lightning.Factories
  import LightningWeb.ApiUsersHelpers

  alias Lightning.Accounts
  alias Lightning.Accounts.User

  setup :json_conn_with_service_account

  describe "PATCH /api/users/:id" do
    setup %{conn: conn, account: account} do
      user =
        insert(:user,
          email: "patched@example.com",
          first_name: "Ada",
          last_name: "Lovelace"
        )

      %{conn: with_scopes(conn, account, ["users:write"]), user: user}
    end

    test "changes the names and role and answers 200 as a create would", %{
      conn: conn,
      user: user
    } do
      conn =
        patch(conn, ~p"/api/users/#{user.id}", %{
          first_name: "Grace",
          last_name: "Hopper",
          role: "superuser"
        })

      assert json_response(conn, 200) == %{
               "data" => %{
                 "type" => "users",
                 "id" => user.id,
                 "attributes" => %{
                   "email" => "patched@example.com",
                   "first_name" => "Grace",
                   "last_name" => "Hopper",
                   "role" => "superuser"
                 },
                 "links" => %{"self" => user_url(user.id)}
               }
             }

      assert %User{first_name: "Grace", last_name: "Hopper", role: :superuser} =
               Accounts.get_user(user.id)
    end

    test "a user another request deletes mid-update answers 409 concurrent_edit",
         %{conn: conn, user: user} do
      after_first_query("users", user.id, fn id ->
        Repo.query!("DELETE FROM users WHERE id = $1", [id])
      end)

      conn
      |> patch(~p"/api/users/#{user.id}", %{first_name: "Grace"})
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(user)
    end

    test "leaves the password alone unless one is given", %{
      conn: conn,
      user: user
    } do
      assert conn
             |> patch(~p"/api/users/#{user.id}", %{first_name: "Grace"})
             |> json_response(200)

      assert Accounts.get_user_by_email_and_password(user.email, "hello world!")
    end

    test "changes the password and signs the user out of its sessions only", %{
      conn: conn,
      user: user
    } do
      session = Accounts.generate_user_session_token(user)
      api_token = Accounts.generate_api_token(user)
      watch_sockets(user)

      assert conn
             |> patch(~p"/api/users/#{user.id}", %{password: password()})
             |> json_response(200)

      assert Accounts.get_user_by_email_and_password(user.email, password())
      refute Accounts.get_user_by_email_and_password(user.email, "hello world!")
      refute Accounts.get_user_by_session_token(session)
      assert Accounts.get_user_by_api_token(api_token)
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    end

    test "changes nothing when given the password the user already has", %{
      conn: conn,
      user: user
    } do
      session = Accounts.generate_user_session_token(user)
      watch_sockets(user)

      for _ <- 1..2 do
        assert conn
               |> patch(~p"/api/users/#{user.id}", %{password: "hello world!"})
               |> json_response(200)
      end

      assert Accounts.get_user_by_session_token(session)
      assert Accounts.get_user(user.id).hashed_password == user.hashed_password
      assert %{entries: []} = Lightning.Auditing.list_all()
      refute_received %Phoenix.Socket.Broadcast{event: "disconnect"}
    end

    test "refuses a password bcrypt would read as the current one", %{
      conn: conn,
      user: user
    } do
      conn
      |> patch(~p"/api/users/#{user.id}", %{password: "hello world!\0anything"})
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/password",
          "code" => "format",
          "detail" => "can't contain a NUL character"
        }
      ])
    end

    test "signs the user out when its role changes", %{conn: conn, user: user} do
      session = Accounts.generate_user_session_token(user)

      assert conn
             |> patch(~p"/api/users/#{user.id}", %{role: "superuser"})
             |> json_response(200)

      refute Accounts.get_user_by_session_token(session)
    end

    test "keeps the sessions when only the names change", %{
      conn: conn,
      user: user
    } do
      session = Accounts.generate_user_session_token(user)
      watch_sockets(user)

      assert conn
             |> patch(~p"/api/users/#{user.id}", %{
               first_name: "Grace",
               role: "user"
             })
             |> json_response(200)

      assert Accounts.get_user_by_session_token(session)
      refute_received %Phoenix.Socket.Broadcast{event: "disconnect"}
    end

    test "confirms an unconfirmed user and never unconfirms one", %{
      conn: conn,
      user: user
    } do
      assert conn
             |> patch(~p"/api/users/#{user.id}", %{confirmed: false})
             |> json_response(200)

      refute Accounts.get_user(user.id).confirmed_at

      assert conn
             |> patch(~p"/api/users/#{user.id}", %{confirmed: true})
             |> json_response(200)

      assert %{confirmed_at: confirmed_at} = Accounts.get_user(user.id)
      assert confirmed_at

      confirmed =
        insert(:user, confirmed_at: ~U[2020-01-01 00:00:00Z])

      for confirmed_param <- [true, false] do
        assert conn
               |> patch(~p"/api/users/#{confirmed.id}", %{
                 confirmed: confirmed_param
               })
               |> json_response(200)

        assert Accounts.get_user(confirmed.id).confirmed_at ==
                 ~U[2020-01-01 00:00:00Z]
      end
    end

    test "refuses a key beyond the five it takes, the email included, with the body's other errors, changing nothing",
         %{conn: conn, user: user} do
      unknown = fn key ->
        %{
          "pointer" => "#/" <> key,
          "code" => "unknown_key",
          "detail" => "is not accepted"
        }
      end

      for {body, entries} <- [
            {%{email: "new@example.com"}, [unknown.("email")]},
            {%{first_name: "Grace", password: "short", disabled: true},
             [
               unknown.("disabled"),
               %{
                 "pointer" => "#/password",
                 "code" => "too_short",
                 "detail" => "should be at least 12 character(s)"
               }
             ]}
          ] do
        conn
        |> patch(~p"/api/users/#{user.id}", body)
        |> assert_problem(422, :invalid, entries)
      end

      assert %User{first_name: "Ada", email: "patched@example.com"} =
               Accounts.get_user(user.id)

      assert Accounts.get_user_by_email_and_password(user.email, "hello world!")
      assert %{entries: []} = Lightning.Auditing.list_all()
    end

    test "answers 422 with an entry at each field that breaks a rule, changing nothing",
         %{conn: conn, user: user} do
      conn
      |> patch(~p"/api/users/#{user.id}", %{
        first_name: "  ",
        last_name: "a\0b",
        password: "short",
        role: "admin",
        confirmed: "perhaps"
      })
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/first_name",
          "code" => "required",
          "detail" => "can't be blank"
        },
        %{
          "pointer" => "#/last_name",
          "code" => "format",
          "detail" => "can't contain control characters"
        },
        %{
          "pointer" => "#/password",
          "code" => "too_short",
          "detail" => "should be at least 12 character(s)"
        },
        %{
          "pointer" => "#/role",
          "code" => "not_allowed",
          "detail" => "is invalid"
        },
        %{"pointer" => "#/confirmed", "code" => "type", "detail" => "is invalid"}
      ])

      assert %User{first_name: "Ada", last_name: "Lovelace", role: :user} =
               Accounts.get_user(user.id)

      assert Accounts.get_user_by_email_and_password(user.email, "hello world!")
      assert %{entries: []} = Lightning.Auditing.list_all()
    end

    test "answers 422 for a blank last name and a NUL character in a password, changing nothing",
         %{conn: conn, user: user} do
      conn
      |> patch(~p"/api/users/#{user.id}", %{
        last_name: "",
        password: "abcdefghijkl\0anything"
      })
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/last_name",
          "code" => "required",
          "detail" => "can't be blank"
        },
        %{
          "pointer" => "#/password",
          "code" => "format",
          "detail" => "can't contain a NUL character"
        }
      ])

      assert %User{first_name: "Ada", last_name: "Lovelace", role: :user} =
               Accounts.get_user(user.id)

      assert Accounts.get_user_by_email_and_password(user.email, "hello world!")
      assert %{entries: []} = Lightning.Auditing.list_all()
    end

    test "answers 404 for a user that doesn't exist", %{conn: conn} do
      conn
      |> patch(~p"/api/users/#{Ecto.UUID.generate()}", %{first_name: "A"})
      |> assert_problem(404, :not_found, [])

      conn
      |> patch(~p"/api/users/not-a-uuid", %{first_name: "A"})
      |> assert_problem(404, :not_found, [])
    end

    test "records what changed, with the service account as the actor", %{
      conn: conn,
      account: account,
      user: user
    } do
      assert conn
             |> patch(~p"/api/users/#{user.id}", %{
               first_name: "Grace",
               last_name: "Lovelace",
               password: password()
             })
             |> json_response(200)

      assert %{entries: [audit]} = Lightning.Auditing.list_all()

      assert %{
               item_type: "user",
               event: "updated",
               item_id: item_id,
               actor_type: :service_account,
               metadata: %{"password_changed" => true}
             } = audit

      assert item_id == user.id
      assert audit.actor_id == account.uuid
      assert audit.changes.before == %{"first_name" => "Ada"}
      assert audit.changes.after == %{"first_name" => "Grace"}
      refute inspect(audit) =~ password()
      refute inspect(audit) =~ "$2b$"
    end

    test "records nothing when nothing changes", %{conn: conn, user: user} do
      assert conn
             |> patch(~p"/api/users/#{user.id}", %{
               first_name: "Ada",
               role: "user",
               confirmed: false
             })
             |> json_response(200)

      assert %{entries: []} = Lightning.Auditing.list_all()
    end
  end

  describe "superuser changes" do
    setup %{conn: conn, account: account} do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:lightning, :accounts, :superuser_changed]
        ])

      on_exit(fn -> :telemetry.detach(ref) end)

      %{conn: with_scopes(conn, account, ["users:write"]), ref: ref}
    end

    defp create_user(conn, role) do
      conn
      |> post(~p"/api/users", %{
        email: "#{role}-#{System.unique_integer([:positive])}@example.com",
        password: password(),
        first_name: "Some",
        last_name: "One",
        role: role
      })
      |> json_response(201)
      |> get_in(["data", "id"])
    end

    defp assert_superuser_change(ref, change, user_id, account) do
      assert_receive {[:lightning, :accounts, :superuser_changed], ^ref,
                      %{count: 1},
                      %{
                        change: ^change,
                        user_id: ^user_id,
                        actor_type: :service_account,
                        actor_id: actor_id
                      }}

      assert actor_id == account.id
    end

    test "report a superuser created", %{conn: conn, account: account, ref: ref} do
      id = create_user(conn, "superuser")

      assert_superuser_change(ref, :created, id, account)
    end

    test "report a user made a superuser", %{
      conn: conn,
      account: account,
      ref: ref
    } do
      user = insert(:user)

      conn
      |> patch(~p"/api/users/#{user.id}", %{role: "superuser"})
      |> json_response(200)

      assert_superuser_change(ref, :granted, user.id, account)
    end

    test "report a superuser's password changing", %{
      conn: conn,
      account: account,
      ref: ref
    } do
      user = insert(:user, role: :superuser)

      conn
      |> patch(~p"/api/users/#{user.id}", %{password: password()})
      |> json_response(200)

      assert_superuser_change(ref, :password_changed, user.id, account)
    end

    test "say nothing for an ordinary user, or a superuser's names", %{
      conn: conn,
      account: account,
      ref: ref
    } do
      user = insert(:user)
      superuser = insert(:user, role: :superuser)

      create_user(conn, "user")

      conn
      |> patch(~p"/api/users/#{user.id}", %{password: password()})
      |> json_response(200)

      conn
      |> patch(~p"/api/users/#{superuser.id}", %{first_name: "Renamed"})
      |> json_response(200)

      # The handler hears every test running at the same time, so only this
      # test's own service account counts.
      actor_id = account.id

      refute_received {[:lightning, :accounts, :superuser_changed], ^ref, _,
                       %{actor_id: ^actor_id}}
    end
  end
end
