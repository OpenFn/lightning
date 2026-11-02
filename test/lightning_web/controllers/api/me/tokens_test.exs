defmodule LightningWeb.API.Me.TokensTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers

  alias Lightning.Accounts
  alias Lightning.Accounts.UserToken
  alias Lightning.Repo

  defp bearer(token) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer " <> token)
  end

  defp entry_id(user, token),
    do: Repo.get_by!(UserToken, user_id: user.id, token: token).id

  defp masked(token),
    do: String.slice(token, 0, 5) <> "…" <> String.slice(token, -5, 5)

  describe "listing" do
    test "lists the person's personal access tokens, newest first, each masked" do
      user = insert(:user)
      older = Accounts.generate_api_token(user)
      newer = Accounts.generate_api_token(user)
      _someone_elses = Accounts.generate_api_token(insert(:user))

      Repo.update_all(
        from(t in UserToken, where: t.token == ^older),
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -60)]
      )

      conn = newer |> bearer() |> get(~p"/api/me/tokens")

      # Using a token stamps when it was last used.
      stored =
        Map.new(
          Repo.all(from t in UserToken, where: t.user_id == ^user.id),
          &{&1.token, &1}
        )

      assert %DateTime{} = stored[newer].last_used_at

      assert json_response(conn, 200) == %{
               "data" =>
                 for token <- [newer, older] do
                   %{
                     "id" => stored[token].id,
                     "token" => masked(token),
                     "inserted_at" =>
                       DateTime.to_iso8601(stored[token].inserted_at),
                     "last_used_at" =>
                       stored[token].last_used_at &&
                         DateTime.to_iso8601(stored[token].last_used_at)
                   }
                 end
             }
    end

    test "lists them for a session token too" do
      user = insert(:user)
      token = Accounts.generate_api_token(user)

      conn = build_conn() |> session_conn(user) |> get(~p"/api/me/tokens")

      assert [%{"token" => shown}] = json_response(conn, 200)["data"]
      assert shown == masked(token)
    end
  end

  describe "creating" do
    test "creates a token on a stepped-up session and shows it whole, once" do
      user = insert(:user)

      conn =
        build_conn()
        |> session_conn(user, stepped_up: true)
        |> post(~p"/api/me/tokens")

      assert %{"data" => %{"token" => token} = data} = json_response(conn, 201)
      assert get_resp_header(conn, "cache-control") == ["no-store"]

      %UserToken{} = stored = Repo.get_by!(UserToken, token: token)

      assert data == %{
               "id" => stored.id,
               "token" => token,
               "inserted_at" => DateTime.to_iso8601(stored.inserted_at),
               "last_used_at" => nil
             }

      assert Accounts.get_user_by_api_token(token).id == user.id
    end

    test "answers a session stepped up more than five minutes ago with step_up_required" do
      user = insert(:user)

      build_conn()
      |> session_conn(user)
      |> step_up(user, 301)
      |> post(~p"/api/me/tokens")
      |> assert_problem(403, :step_up_required, [])

      assert Accounts.list_api_tokens(user) == []
    end
  end

  describe "revoking" do
    test "revokes one of the person's tokens on a session, and answers 204" do
      user = insert(:user)
      token = Accounts.generate_api_token(user)
      kept = Accounts.generate_api_token(user)

      conn =
        build_conn()
        |> session_conn(user)
        |> delete(~p"/api/me/tokens/#{entry_id(user, token)}")

      assert conn.status == 204
      assert conn.resp_body == ""
      refute Accounts.get_user_by_api_token(token)
      assert Accounts.get_user_by_api_token(kept)
    end

    test "lets a token revoke itself, after which it is refused" do
      user = insert(:user)
      token = Accounts.generate_api_token(user)

      conn =
        token |> bearer() |> delete(~p"/api/me/tokens/#{entry_id(user, token)}")

      assert conn.status == 204

      token
      |> bearer()
      |> get(~p"/api/me/tokens")
      |> assert_unauthenticated(:invalid_token, [
        ~s(Bearer error="invalid_token")
      ])
    end

    test "answers an id that names no token of the person's with not_found, and one that isn't a UUID with invalid_parameter" do
      user = insert(:user)
      other = insert(:user)
      theirs = Accounts.generate_api_token(other)
      conn = session_conn(build_conn(), user)

      session_id =
        Repo.get_by!(UserToken, user_id: user.id, context: "session").id

      for id <- [entry_id(other, theirs), session_id, Ecto.UUID.generate()] do
        conn
        |> delete(~p"/api/me/tokens/#{id}")
        |> assert_problem(404, :not_found, [])
      end

      conn
      |> delete(~p"/api/me/tokens/not-a-uuid")
      |> assert_problem(400, :invalid_parameter, [
        not_a_uuid_entry(%{"path" => "id"})
      ])

      assert Accounts.get_user_by_api_token(theirs)
      assert Repo.get(UserToken, session_id)
    end
  end

  describe "stale writes" do
    # Revoking is one statement, so there is no read for another request to
    # overtake: a token it revoked first is simply not there.
    test "a token another request revoked first is not found" do
      user = insert(:user)
      token = Accounts.generate_api_token(user)
      id = entry_id(user, token)
      :ok = Accounts.revoke_api_token(user, id)

      build_conn()
      |> session_conn(user)
      |> delete(~p"/api/me/tokens/#{id}")
      |> assert_problem(404, :not_found, [])
    end
  end
end
