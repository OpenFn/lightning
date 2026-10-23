defmodule LightningWeb.API.UsersListingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import Lightning.Factories
  import LightningWeb.ApiUsersHelpers

  setup :json_conn_with_service_account

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

    test "page links carry the email filter and no other query parameter", %{
      conn: conn
    } do
      insert(:user, email: "linked@example.com")

      assert %{"links" => links} =
               conn
               |> get(
                 ~p"/api/users?email=linked@example.com&page_size=5&foo=bar"
               )
               |> json_response(200)

      first =
        "#{LightningWeb.Endpoint.url()}/api/users?email=linked%40example.com&page=1&page_size=5"

      assert links == %{
               "self" => first,
               "first" => first,
               "last" => first,
               "next" => nil,
               "prev" => nil
             }
    end

    test "page links carry only the page and page size without a filter", %{
      conn: conn
    } do
      insert_list(3, :user)

      base = "#{LightningWeb.Endpoint.url()}/api/users"

      for {query, expected} <- [
            {"page=1&page_size=2&foo=bar",
             %{
               "self" => base <> "?page=1&page_size=2",
               "first" => base <> "?page=1&page_size=2",
               "last" => base <> "?page=2&page_size=2",
               "next" => base <> "?page=2&page_size=2",
               "prev" => nil
             }},
            {"page=2&page_size=2&foo=bar",
             %{
               "self" => base <> "?page=2&page_size=2",
               "first" => base <> "?page=1&page_size=2",
               "last" => base <> "?page=2&page_size=2",
               "next" => nil,
               "prev" => base <> "?page=1&page_size=2"
             }}
          ] do
        assert %{"links" => links} =
                 conn |> get("/api/users?" <> query) |> json_response(200)

        assert links == expected, query
      end
    end

    test "never answers with more than 100 users a page", %{conn: conn} do
      insert_list(101, :user)

      assert %{"data" => data, "links" => %{"next" => next}} =
               conn
               |> get(~p"/api/users?page_size=100000000")
               |> json_response(200)

      assert length(data) == 100
      assert next =~ "page=2"
    end

    test "falls back to the default page for page params it can't read", %{
      conn: conn
    } do
      insert_list(11, :user)

      for query <- [
            "page=abc&page_size=xyz",
            "page[]=2&page_size[]=2",
            "page=-1&page_size=0"
          ] do
        assert %{"data" => data, "links" => %{"prev" => nil}} =
                 conn |> get("/api/users?" <> query) |> json_response(200)

        assert length(data) == 10, query
      end
    end

    test "answers a page number past the end with the last page", %{conn: conn} do
      insert_list(11, :user)

      assert %{"data" => [_ | _], "links" => %{"next" => nil}} =
               conn
               |> get(~p"/api/users?page=99999999999999999999")
               |> json_response(200)
    end

    test "answers 400 invalid_parameter for an email filter that isn't a string",
         %{conn: conn} do
      insert(:user, email: "x@example.com")

      conn
      |> get(~p"/api/users?email[]=x@example.com")
      |> assert_problem(400, :invalid_parameter, [
        %{"parameter" => "email", "code" => "type", "detail" => "is invalid"}
      ])
    end
  end

  describe "GET /api/users/:id" do
    test "shows a user, with a self link that names it", %{
      conn: conn,
      account: account
    } do
      user = insert(:user, email: "shown@example.com")
      conn = with_scopes(conn, account, ["users:read"])

      assert %{"data" => %{"id" => id, "links" => %{"self" => self}}} =
               conn |> get(~p"/api/users/#{user.id}") |> json_response(200)

      assert id == user.id
      assert self == user_url(user.id)
    end

    test "answers 404 for a user that doesn't exist or an id that isn't a UUID",
         %{conn: conn, account: account} do
      conn = with_scopes(conn, account, ["users:read"])

      conn
      |> get(~p"/api/users/#{Ecto.UUID.generate()}")
      |> assert_problem(404, :not_found, [])

      conn
      |> get(~p"/api/users/not-a-uuid")
      |> assert_problem(404, :not_found, [])
    end
  end
end
