defmodule LightningWeb.API.UserControllerTest do
  use LightningWeb.ConnCase, async: true

  import ExUnit.CaptureLog
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.ServiceAccount.AccessToken
  alias LightningWeb.UserAuth

  @password "a long enough password"

  setup %{conn: conn} do
    {account, _private_key} = service_account_with_key()
    Mox.stub(Lightning.MockConfig, :service_account, fn -> account end)

    %{
      conn: put_req_header(conn, "accept", "application/json"),
      account: account
    }
  end

  defp with_scopes(conn, account, scopes) do
    put_req_header(
      conn,
      "authorization",
      "Bearer " <> AccessToken.issue(account, scopes)
    )
  end

  defp user_url(id), do: "#{LightningWeb.Endpoint.url()}/api/users/#{id}"

  defp watch_sockets(user) do
    LightningWeb.Endpoint.subscribe(UserAuth.user_socket_topic(user))
    LightningWeb.Endpoint.subscribe(UserAuth.live_socket_topic(user))
  end

  describe "POST /api/users" do
    setup %{conn: conn, account: account} do
      %{conn: with_scopes(conn, account, ["users:write"])}
    end

    test "creates a user with names and answers 201", %{conn: conn} do
      conn =
        post(conn, ~p"/api/users", %{
          email: "Ada@Example.com",
          password: @password,
          first_name: "Ada",
          last_name: "Lovelace"
        })

      assert %{"data" => %{"id" => id} = data} = json_response(conn, 201)

      assert data == %{
               "type" => "users",
               "id" => id,
               "attributes" => %{
                 "email" => "ada@example.com",
                 "first_name" => "Ada",
                 "last_name" => "Lovelace",
                 "role" => "user"
               },
               "links" => %{"self" => user_url(id)}
             }

      assert %User{role: :user, confirmed_at: nil} =
               Accounts.get_user_by_email("ada@example.com")
    end

    test "creates a confirmed superuser", %{conn: conn} do
      conn =
        post(conn, ~p"/api/users", %{
          email: "root@example.com",
          password: @password,
          first_name: "Root",
          last_name: "Admin",
          role: "superuser",
          confirmed: true
        })

      assert %{
               "data" => %{
                 "attributes" => %{
                   "email" => "root@example.com",
                   "role" => "superuser"
                 }
               }
             } = json_response(conn, 201)

      user = Accounts.get_user_by_email("root@example.com")
      assert %User{role: :superuser} = user
      assert user.confirmed_at
      assert Accounts.get_user_by_email_and_password(user.email, @password)
    end

    test "ignores keys beyond the six it takes", %{conn: conn} do
      conn =
        post(conn, ~p"/api/users", %{
          email: "sneaky@example.com",
          password: @password,
          first_name: "Sneaky",
          last_name: "User",
          support_user: true,
          disabled: true,
          hashed_password: "not-a-hash",
          confirmed_at: "2020-01-01T00:00:00Z"
        })

      assert json_response(conn, 201)

      assert %User{support_user: false, disabled: false, confirmed_at: nil} =
               user = Accounts.get_user_by_email("sneaky@example.com")

      assert Accounts.get_user_by_email_and_password(user.email, @password)
    end

    test "answers 409 with the existing user when the email is taken in any case",
         %{conn: conn} do
      existing =
        insert(:user,
          email: "taken@example.com",
          first_name: "Tak",
          last_name: "En",
          role: :superuser
        )

      conn =
        post(conn, ~p"/api/users", %{
          email: "TAKEN@example.com",
          password: @password,
          first_name: "Other",
          last_name: "Person",
          role: "user"
        })

      assert json_response(conn, 409) == %{
               "data" => %{
                 "type" => "users",
                 "id" => existing.id,
                 "attributes" => %{
                   "email" => "taken@example.com",
                   "first_name" => "Tak",
                   "last_name" => "En",
                   "role" => "superuser"
                 },
                 "links" => %{"self" => user_url(existing.id)}
               }
             }
    end

    test "answers 422 keyed by the request's field names", %{conn: conn} do
      assert json_response(
               post(conn, ~p"/api/users", %{
                 email: "not-an-email",
                 password: "short",
                 role: "admin",
                 confirmed: "perhaps",
                 first_name: String.duplicate("a", 256),
                 last_name: "Long"
               }),
               422
             ) == %{
               "errors" => %{
                 "first_name" => ["should be at most 255 character(s)"],
                 "email" => ["Email address not valid."],
                 "password" => ["Password minimum length is 12 characters."],
                 "role" => ["is invalid"],
                 "confirmed" => ["is invalid"]
               }
             }

      assert json_response(
               post(conn, ~p"/api/users", %{
                 email: "nul@example.com",
                 password: "abcdefghijkl\0anything",
                 first_name: "Nul",
                 last_name: "a\0b"
               }),
               422
             ) == %{
               "errors" => %{
                 "password" => ["can't contain a NUL character"],
                 "last_name" => ["can't contain control characters"]
               }
             }

      assert json_response(post(conn, ~p"/api/users", %{}), 422) == %{
               "errors" => %{
                 "email" => ["This field can't be blank."],
                 "password" => ["This field can't be blank."],
                 "first_name" => ["This field can't be blank."],
                 "last_name" => ["This field can't be blank."]
               }
             }
    end

    test "answers 422 for a user without both names, for either role", %{
      conn: conn
    } do
      for role <- ["user", "superuser"],
          {names, blank} <- [
            {%{}, ["first_name", "last_name"]},
            {%{first_name: "", last_name: "  "}, ["first_name", "last_name"]},
            {%{first_name: "Ada"}, ["last_name"]},
            {%{first_name: "\u200B", last_name: "Lovelace"}, ["first_name"]}
          ] do
        email = "nameless-#{System.unique_integer([:positive])}@example.com"

        conn =
          post(
            conn,
            ~p"/api/users",
            Map.merge(%{email: email, password: @password, role: role}, names)
          )

        assert %{"errors" => errors} = json_response(conn, 422)
        assert errors |> Map.keys() |> Enum.sort() == blank
        refute Accounts.get_user_by_email(email)
      end
    end

    test "records an audit event whose actor is the service account", %{
      conn: conn,
      account: account
    } do
      conn =
        post(conn, ~p"/api/users", %{
          email: "audited@example.com",
          password: @password,
          first_name: "Audi",
          last_name: "Ted"
        })

      assert %{"data" => %{"id" => id}} = json_response(conn, 201)

      assert %{entries: [audit]} = Lightning.Auditing.list_all()

      assert %{
               item_type: "user",
               event: "created",
               item_id: ^id,
               actor_type: :service_account,
               actor_display: %{label: "Service account", identifier: identifier}
             } = audit

      assert identifier == account.id

      assert audit.actor_id == account.uuid
      refute Map.has_key?(audit.changes.after, "hashed_password")
      refute inspect(audit.changes) =~ @password
    end

    test "needs users:write", %{conn: conn, account: account} do
      conn =
        conn
        |> with_scopes(account, ["users:read"])
        |> post(~p"/api/users", %{email: "no@example.com", password: @password})

      assert json_response(conn, 403) == %{"error" => "insufficient_scope"}
      refute Accounts.get_user_by_email("no@example.com")
    end

    test "refuses a personal access token", %{conn: conn} do
      token = insert(:user, role: :superuser) |> Accounts.generate_api_token()

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> post(~p"/api/users", %{email: "no@example.com", password: @password})

      assert json_response(conn, 401) == %{"error" => "invalid_token"}
    end
  end

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
             |> patch(~p"/api/users/#{user.id}", %{password: @password})
             |> json_response(200)

      assert Accounts.get_user_by_email_and_password(user.email, @password)
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
      assert json_response(
               patch(conn, ~p"/api/users/#{user.id}", %{
                 password: "hello world!\0anything"
               }),
               422
             ) == %{
               "errors" => %{"password" => ["can't contain a NUL character"]}
             }
    end

    test "needs no names for a user stored without them", %{conn: conn} do
      user = insert(:user, first_name: nil, last_name: nil)

      assert conn
             |> patch(~p"/api/users/#{user.id}", %{role: "superuser"})
             |> json_response(200)

      assert %User{role: :superuser} = Accounts.get_user(user.id)
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

    test "ignores the email and keys it doesn't take", %{conn: conn, user: user} do
      assert conn
             |> patch(~p"/api/users/#{user.id}", %{
               email: "moved@example.com",
               support_user: true,
               disabled: true,
               hashed_password: "not-a-hash",
               confirmed_at: "2020-01-01T00:00:00Z"
             })
             |> json_response(200)

      assert %User{
               email: "patched@example.com",
               support_user: false,
               disabled: false,
               confirmed_at: nil
             } = Accounts.get_user(user.id)

      assert Accounts.get_user_by_email_and_password(user.email, "hello world!")
    end

    test "answers 422 keyed by the request's field names", %{
      conn: conn,
      user: user
    } do
      assert json_response(
               patch(conn, ~p"/api/users/#{user.id}", %{
                 first_name: "  ",
                 last_name: "a\0b",
                 password: "short",
                 role: "admin",
                 confirmed: "perhaps"
               }),
               422
             ) == %{
               "errors" => %{
                 "first_name" => ["This field can't be blank."],
                 "last_name" => ["can't contain control characters"],
                 "password" => ["Password minimum length is 12 characters."],
                 "role" => ["is invalid"],
                 "confirmed" => ["is invalid"]
               }
             }

      assert json_response(
               patch(conn, ~p"/api/users/#{user.id}", %{
                 last_name: "",
                 password: "abcdefghijkl\0anything"
               }),
               422
             ) == %{
               "errors" => %{
                 "last_name" => ["This field can't be blank."],
                 "password" => ["can't contain a NUL character"]
               }
             }

      assert %User{first_name: "Ada", last_name: "Lovelace", role: :user} =
               Accounts.get_user(user.id)

      assert Accounts.get_user_by_email_and_password(user.email, "hello world!")
      assert %{entries: []} = Lightning.Auditing.list_all()
    end

    test "answers 404 for a user that doesn't exist", %{conn: conn} do
      assert conn
             |> patch(~p"/api/users/#{Ecto.UUID.generate()}", %{first_name: "A"})
             |> json_response(404)

      assert conn
             |> patch(~p"/api/users/not-a-uuid", %{first_name: "A"})
             |> json_response(404)
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
               password: @password
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
      refute inspect(audit) =~ @password
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

    test "needs users:write", %{conn: conn, account: account, user: user} do
      conn =
        conn
        |> with_scopes(account, ["users:read"])
        |> patch(~p"/api/users/#{user.id}", %{first_name: "Grace"})

      assert json_response(conn, 403) == %{"error" => "insufficient_scope"}
      assert %User{first_name: "Ada"} = Accounts.get_user(user.id)
    end

    test "refuses a personal access token", %{conn: conn, user: user} do
      token = insert(:user, role: :superuser) |> Accounts.generate_api_token()

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> patch(~p"/api/users/#{user.id}", %{first_name: "Grace"})

      assert json_response(conn, 401) == %{"error" => "invalid_token"}
      assert %User{first_name: "Ada"} = Accounts.get_user(user.id)
    end
  end

  describe "superuser changes" do
    setup %{conn: conn, account: account} do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:lightning, :service_account, :superuser_changed]
        ])

      %{conn: with_scopes(conn, account, ["users:write"]), ref: ref}
    end

    defp create_user(conn, role) do
      conn
      |> post(~p"/api/users", %{
        email: "#{role}-#{System.unique_integer([:positive])}@example.com",
        password: @password,
        first_name: "Some",
        last_name: "One",
        role: role
      })
      |> json_response(201)
      |> get_in(["data", "id"])
    end

    defp assert_superuser_change(ref, change, user_id, account) do
      assert_receive {[:lightning, :service_account, :superuser_changed], ^ref,
                      %{count: 1},
                      %{
                        change: ^change,
                        user_id: ^user_id,
                        service_account_id: service_account_id
                      }}

      assert service_account_id == account.id
    end

    test "warn when a superuser is created", %{
      conn: conn,
      account: account,
      ref: ref
    } do
      {id, log} =
        with_log([level: :warning], fn -> create_user(conn, "superuser") end)

      assert log =~ "Service account #{account.id} created superuser #{id}"
      assert_superuser_change(ref, :created, id, account)
    end

    test "warn when a user is made a superuser", %{
      conn: conn,
      account: account,
      ref: ref
    } do
      user = insert(:user)

      log =
        capture_log([level: :warning], fn ->
          conn
          |> patch(~p"/api/users/#{user.id}", %{role: "superuser"})
          |> json_response(200)
        end)

      assert log =~
               "Service account #{account.id} made user #{user.id} a superuser"

      assert_superuser_change(ref, :granted, user.id, account)
    end

    test "warn when a superuser's password changes", %{
      conn: conn,
      account: account,
      ref: ref
    } do
      user = insert(:user, role: :superuser)

      log =
        capture_log([level: :warning], fn ->
          conn
          |> patch(~p"/api/users/#{user.id}", %{password: @password})
          |> json_response(200)
        end)

      assert log =~
               "Service account #{account.id} changed the password of superuser #{user.id}"

      assert_superuser_change(ref, :password_changed, user.id, account)
    end

    test "say nothing for an ordinary user, or a superuser's names", %{
      conn: conn,
      ref: ref
    } do
      user = insert(:user)
      superuser = insert(:user, role: :superuser)

      log =
        capture_log([level: :warning], fn ->
          create_user(conn, "user")

          conn
          |> patch(~p"/api/users/#{user.id}", %{password: @password})
          |> json_response(200)

          conn
          |> patch(~p"/api/users/#{superuser.id}", %{first_name: "Renamed"})
          |> json_response(200)
        end)

      refute log =~ "Service account"

      refute_received {[:lightning, :service_account, :superuser_changed], ^ref,
                       _, _}
    end
  end

  describe "GET /api/users" do
    setup %{conn: conn, account: account} do
      %{conn: with_scopes(conn, account, ["users:read"])}
    end

    test "finds a user by email without regard to case", %{conn: conn} do
      user = insert(:user, email: "findme@example.com", first_name: "Find")
      insert(:user)

      assert %{
               "data" => [
                 %{
                   "id" => id,
                   "attributes" => %{
                     "email" => "findme@example.com",
                     "first_name" => "Find"
                   }
                 }
               ],
               "links" => %{"self" => _}
             } =
               conn
               |> get(~p"/api/users?email=FindMe@Example.COM")
               |> json_response(200)

      assert id == user.id

      assert %{"data" => []} =
               conn
               |> get(~p"/api/users?email=nobody@example.com")
               |> json_response(200)
    end

    test "never includes a password or its hash", %{conn: conn} do
      insert(:user, email: "secret@example.com")

      body =
        conn |> get(~p"/api/users?email=secret@example.com") |> response(200)

      refute body =~ "password"
      refute body =~ "$2b$"
    end

    test "is paginated", %{conn: conn} do
      insert_list(3, :user)

      assert %{"data" => [_, _], "links" => %{"next" => _}} =
               conn |> get(~p"/api/users?page_size=2") |> json_response(200)
    end

    test "needs users:read", %{conn: conn, account: account} do
      conn =
        conn
        |> with_scopes(account, ["users:write"])
        |> get(~p"/api/users?email=a@example.com")

      assert json_response(conn, 403) == %{"error" => "insufficient_scope"}
    end

    test "refuses a personal access token", %{conn: conn} do
      token = insert(:user, role: :superuser) |> Accounts.generate_api_token()

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> get(~p"/api/users?email=a@example.com")

      assert json_response(conn, 401) == %{"error" => "invalid_token"}
    end
  end

  describe "GET /api/users/:id" do
    test "shows the user its self link names", %{conn: conn, account: account} do
      user = insert(:user, email: "shown@example.com")
      conn = with_scopes(conn, account, ["users:read"])

      assert %{"data" => %{"id" => id, "links" => %{"self" => self}}} =
               conn |> get(~p"/api/users/#{user.id}") |> json_response(200)

      assert id == user.id
      assert self == user_url(user.id)

      assert conn
             |> get(~p"/api/users/#{Ecto.UUID.generate()}")
             |> json_response(404)

      assert conn |> get(~p"/api/users/not-a-uuid") |> json_response(404)
    end
  end
end
