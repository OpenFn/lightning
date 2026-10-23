defmodule LightningWeb.API.UsersCreatingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import Lightning.Factories
  import LightningWeb.ApiUsersHelpers

  alias Lightning.Accounts
  alias Lightning.Accounts.User

  setup :json_conn_with_service_account

  describe "POST /api/users" do
    setup %{conn: conn, account: account} do
      %{conn: with_scopes(conn, account, ["users:write"])}
    end

    test "creates a user with names and answers 201", %{conn: conn} do
      conn =
        post(conn, ~p"/api/users", %{
          email: "Ada@Example.com",
          password: password(),
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
          password: password(),
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
      assert Accounts.get_user_by_email_and_password(user.email, password())
    end

    test "refuses a key beyond the six it takes, creating no user", %{
      conn: conn
    } do
      conn
      |> post(~p"/api/users", %{
        email: "colourful@example.com",
        password: password(),
        first_name: "Colour",
        last_name: "Ful",
        colour: "blue"
      })
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/colour",
          "code" => "unknown_key",
          "detail" => "is not accepted"
        }
      ])

      refute Accounts.get_user_by_email("colourful@example.com")
    end

    test "more than one error is a 422 with every entry, never a 409", %{
      conn: conn
    } do
      insert(:user, email: "taken@example.com")

      unknown = fn key ->
        %{
          "pointer" => "#/" <> key,
          "code" => "unknown_key",
          "detail" => "is not accepted"
        }
      end

      for {body, entries} <- [
            {%{
               email: "nopass@example.com",
               first_name: "No",
               last_name: "Pass",
               colour: "blue"
             },
             [
               unknown.("colour"),
               %{
                 "pointer" => "#/password",
                 "code" => "required",
                 "detail" => "can't be blank"
               }
             ]},
            {%{
               email: "taken@example.com",
               password: password(),
               first_name: "Other",
               last_name: "Person",
               support_user: true
             },
             [
               unknown.("support_user"),
               %{
                 "pointer" => "#/email",
                 "code" => "taken",
                 "detail" => "has already been taken"
               }
             ]},
            {%{
               email: "taken@example.com",
               password: "short",
               first_name: "Other",
               last_name: "Person"
             },
             [
               %{
                 "pointer" => "#/email",
                 "code" => "taken",
                 "detail" => "has already been taken"
               },
               %{
                 "pointer" => "#/password",
                 "code" => "too_short",
                 "detail" => "should be at least 12 character(s)"
               }
             ]}
          ] do
        body =
          conn
          |> post(~p"/api/users", body)
          |> assert_problem(422, :invalid, entries)

        refute Map.has_key?(body, "existing")
      end

      refute Accounts.get_user_by_email("nopass@example.com")
    end

    test "answers 409 taken with only the existing user's id when the email is taken in any case",
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
          password: password(),
          first_name: "Other",
          last_name: "Person",
          role: "user"
        })

      body =
        assert_problem(conn, 409, :taken, [
          %{
            "pointer" => "#/email",
            "code" => "taken",
            "detail" => "has already been taken"
          }
        ])

      assert body["existing"] == %{"id" => existing.id}

      assert body |> Map.keys() |> Enum.sort() ==
               ~w(code detail errors existing status title type)
    end

    test "answers 409 taken without existing when the holder is gone by the time it is looked up",
         %{conn: conn} do
      attrs = %{
        "email" => "taken@example.com",
        "password" => password(),
        "first_name" => "Other",
        "last_name" => "Person"
      }

      holder = insert(:user, email: "taken@example.com")

      {:error, refused} =
        Lightning.Extensions.AccountHook.handle_create_user(attrs)

      Lightning.Repo.delete!(holder)

      Mox.expect(Lightning.Extensions.MockAccountHook, :handle_create_user, fn
        ^attrs -> {:error, refused}
      end)

      body =
        conn
        |> post(~p"/api/users", attrs)
        |> assert_problem(409, :taken, [
          %{
            "pointer" => "#/email",
            "code" => "taken",
            "detail" => "has already been taken"
          }
        ])

      refute Map.has_key?(body, "existing")
    end

    test "answers 422 with an entry at each field that breaks a rule", %{
      conn: conn
    } do
      conn
      |> post(~p"/api/users", %{
        email: "not-an-email",
        password: "short",
        role: "admin",
        confirmed: "perhaps",
        first_name: String.duplicate("a", 256),
        last_name: "Long"
      })
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/first_name",
          "code" => "too_long",
          "detail" => "should be at most 255 character(s)"
        },
        %{
          "pointer" => "#/email",
          "code" => "format",
          "detail" => "must be a valid email address"
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
    end

    test "answers 422 for a NUL character in a password and a control character in a name",
         %{conn: conn} do
      conn
      |> post(~p"/api/users", %{
        email: "nul@example.com",
        password: "abcdefghijkl\0anything",
        first_name: "Nul",
        last_name: "a\0b"
      })
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/password",
          "code" => "format",
          "detail" => "can't contain a NUL character"
        },
        %{
          "pointer" => "#/last_name",
          "code" => "format",
          "detail" => "can't contain control characters"
        }
      ])
    end

    test "answers 422 for every field a body leaves out", %{conn: conn} do
      conn
      |> post(~p"/api/users", %{})
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/email",
          "code" => "required",
          "detail" => "can't be blank"
        },
        %{
          "pointer" => "#/password",
          "code" => "required",
          "detail" => "can't be blank"
        },
        %{
          "pointer" => "#/first_name",
          "code" => "required",
          "detail" => "can't be blank"
        },
        %{
          "pointer" => "#/last_name",
          "code" => "required",
          "detail" => "can't be blank"
        }
      ])
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
            Map.merge(%{email: email, password: password(), role: role}, names)
          )

        assert_problem(
          conn,
          422,
          :invalid,
          Enum.map(
            blank,
            &%{
              "pointer" => "#/" <> &1,
              "code" => "required",
              "detail" => "can't be blank"
            }
          )
        )

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
          password: password(),
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
      refute inspect(audit.changes) =~ password()
    end
  end
end
