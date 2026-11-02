defmodule LightningWeb.API.Users.WhoMayReachItTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiUsersHelpers, only: [password: 0]
  import Lightning.Factories

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Repo

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "who may reach it" do
    test "a person's token, a superuser's included, gets the same 403 on every users route for an existing user, an unknown id and a malformed one, and nothing is written",
         %{conn: conn} do
      existing = insert(:user, first_name: "Ada")
      person = insert(:user)
      superuser = insert(:user, role: :superuser)
      before = users()

      for caller <- [person, superuser],
          {verb, id} <- [
            {:list, nil},
            {:get, existing.id},
            {:get, Ecto.UUID.generate()},
            {:get, "not-a-uuid"},
            {:create, nil},
            {:patch, existing.id},
            {:patch, Ecto.UUID.generate()},
            {:patch, "not-a-uuid"}
          ] do
        conn =
          conn
          |> assign_bearer(Accounts.generate_api_token(caller))
          |> reach(verb, id)

        assert_problem(conn, 403, :forbidden, [])
        assert get_resp_header(conn, "www-authenticate") == []
      end

      assert users() == before
    end
  end

  defp reach(conn, :list, nil), do: get(conn, ~p"/api/users")

  defp reach(conn, :get, id), do: get(conn, ~p"/api/users/#{id}")

  defp reach(conn, :create, nil) do
    post(conn, ~p"/api/users", %{
      email: "new-user@example.com",
      password: password(),
      first_name: "Grace",
      last_name: "Hopper",
      role: "superuser",
      confirmed: true
    })
  end

  defp reach(conn, :patch, id),
    do: patch(conn, ~p"/api/users/#{id}", %{first_name: "Grace"})

  defp users do
    User
    |> Repo.all()
    |> Enum.map(&Map.take(&1, [:id, :email, :first_name, :last_name, :role]))
    |> Enum.sort()
  end
end
