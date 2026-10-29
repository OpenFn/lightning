defmodule LightningWeb.API.UsersRequestReadingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import Lightning.Factories
  import LightningWeb.ApiUsersHelpers
  import Lightning.ServiceAccountHelpers, only: [with_scopes: 3]

  alias Lightning.Accounts
  alias Lightning.Accounts.User

  setup :json_conn_with_service_account

  describe "reading a request" do
    setup %{conn: conn, account: account} do
      %{
        conn: with_scopes(conn, account, ["users:read", "users:write"]),
        planted:
          plant_sentinel(%{
            "email" => nil,
            "password" => nil,
            "first_name" => nil,
            "last_name" => nil,
            "role" => nil,
            "confirmed" => nil
          })
      }
    end

    test "answers 400 malformed for a body that is not a JSON object, creating or changing nothing",
         %{conn: conn} do
      user = insert(:user, first_name: "Ada")

      for body <- [
            [%{"first_name" => "Grace", "email" => "array@example.com"}],
            "Grace",
            7
          ],
          path <- [~p"/api/users", ~p"/api/users/#{user.id}"] do
        conn = put_req_header(conn, "content-type", "application/json")
        json = Jason.encode!(body)

        conn =
          if path == ~p"/api/users",
            do: post(conn, path, json),
            else: patch(conn, path, json)

        assert_problem(conn, 400, :malformed, [])
      end

      assert Repo.reload!(user).first_name == "Ada"
      refute Accounts.get_user_by_email("array@example.com")
    end

    test "takes the fields of a create or an update from the body, never the query string",
         %{conn: conn} do
      user = insert(:user, first_name: "Ada")

      conn
      |> post(~p"/api/users?role=superuser", %{
        email: "query@example.com",
        password: password(),
        first_name: "Query",
        last_name: "String"
      })
      |> json_response(201)

      assert %User{role: :user} = Accounts.get_user_by_email("query@example.com")

      conn
      |> patch(~p"/api/users/#{user.id}?role=superuser", %{first_name: "Grace"})
      |> json_response(200)

      assert %User{first_name: "Grace", role: :user} = Accounts.get_user(user.id)
    end

    test "no error answer quotes a value from the request, on any users route",
         %{conn: conn, planted: planted} do
      user = insert(:user)

      conn
      |> post(~p"/api/users", planted)
      |> refute_sentinel()
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/confirmed",
          "code" => "type",
          "detail" => "is invalid"
        },
        %{
          "pointer" => "#/role",
          "code" => "not_allowed",
          "detail" => "is invalid"
        },
        %{
          "pointer" => "#/email",
          "code" => "format",
          "detail" => "must be a valid email address"
        }
      ])

      conn
      |> patch(~p"/api/users/#{user.id}", Map.delete(planted, "email"))
      |> refute_sentinel()
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/confirmed",
          "code" => "type",
          "detail" => "is invalid"
        },
        %{
          "pointer" => "#/role",
          "code" => "not_allowed",
          "detail" => "is invalid"
        }
      ])

      conn
      |> patch(~p"/api/users/#{planted["email"]}", %{first_name: "A"})
      |> refute_sentinel()
      |> assert_problem(400, :invalid_parameter, [
        not_a_uuid_entry(%{"path" => "id"})
      ])

      conn
      |> get("/api/users?email[]=" <> planted["email"])
      |> refute_sentinel()
      |> assert_problem(400, :invalid_parameter, [
        %{"parameter" => "email", "code" => "type", "detail" => "is invalid"}
      ])

      conn
      |> get(~p"/api/users/#{planted["email"]}")
      |> refute_sentinel()
      |> assert_problem(400, :invalid_parameter, [
        not_a_uuid_entry(%{"path" => "id"})
      ])
    end
  end
end
