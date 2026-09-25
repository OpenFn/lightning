defmodule LightningWeb.API.UserControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.ServiceAccount.AccessToken

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

    test "creates a confirmed superuser without names", %{conn: conn} do
      conn =
        post(conn, ~p"/api/users", %{
          email: "root@example.com",
          password: @password,
          role: "superuser",
          confirmed: true
        })

      assert %{
               "data" => %{
                 "attributes" => %{
                   "email" => "root@example.com",
                   "first_name" => nil,
                   "last_name" => nil,
                   "role" => "superuser"
                 }
               }
             } = json_response(conn, 201)

      user = Accounts.get_user_by_email("root@example.com")
      assert %User{role: :superuser, first_name: nil} = user
      assert user.confirmed_at
      assert Accounts.get_user_by_email_and_password(user.email, @password)
    end

    test "ignores keys beyond the six it takes", %{conn: conn} do
      conn =
        post(conn, ~p"/api/users", %{
          email: "sneaky@example.com",
          password: @password,
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
                 first_name: String.duplicate("a", 256)
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

      assert json_response(post(conn, ~p"/api/users", %{}), 422) == %{
               "errors" => %{
                 "email" => ["This field can't be blank."],
                 "password" => ["This field can't be blank."]
               }
             }
    end

    test "records an audit event whose actor is the service account", %{
      conn: conn,
      account: account
    } do
      conn =
        post(conn, ~p"/api/users", %{
          email: "audited@example.com",
          password: @password
        })

      assert %{"data" => %{"id" => id}} = json_response(conn, 201)

      assert %{entries: [audit]} = Lightning.Auditing.list_all()

      assert %{
               item_type: "user",
               event: "created",
               item_id: ^id,
               actor_type: :service_account,
               actor_display: %{label: "Service account", identifier: nil}
             } = audit

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
