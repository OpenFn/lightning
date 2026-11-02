defmodule LightningWeb.API.Users.DeletingTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiUsersHelpers
  import Lightning.RaceHelpers
  import Lightning.ServiceAccountHelpers, only: [with_scopes: 3]
  import Swoosh.TestAssertions

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Accounts.UserToken
  alias Lightning.Repo

  setup :json_conn_with_service_account

  setup %{conn: conn, account: account} do
    %{conn: with_scopes(conn, account, ["users:write"])}
  end

  defp scheduled_at, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp audits(user_id) do
    Repo.all(
      from a in Lightning.Accounts.Audit.base_query(),
        where: a.item_id == ^user_id
    )
  end

  defp tokens(user),
    do:
      Repo.aggregate(from(t in UserToken, where: t.user_id == ^user.id), :count)

  describe "scheduling a user's deletion" do
    test "disables the user, ends their sessions, revokes their tokens and emails them, recorded as the service account",
         %{conn: conn, account: account} do
      Mox.stub(Lightning.MockConfig, :purge_deleted_after_days, fn -> 7 end)
      user = insert(:user)
      Accounts.generate_api_token(user)
      Accounts.generate_user_session_token(user)

      conn = delete(conn, ~p"/api/users/#{user.id}")

      assert response(conn, 204) == ""

      assert %User{disabled: true, scheduled_deletion: %DateTime{} = at} =
               Repo.reload!(user)

      assert DateTime.diff(at, DateTime.utc_now(), :day) in 6..7
      assert tokens(user) == 0

      assert_email_sent(
        to: [{"#{user.first_name} #{user.last_name}", user.email}]
      )

      assert [%{event: "updated", actor_type: :service_account} = audit] =
               audits(user.id)

      assert audit.actor_id == account.uuid
      assert audit.changes.after["disabled"] == true
    end

    test "answers 409 scheduled_for_deletion for a user already scheduled, changing nothing",
         %{conn: conn} do
      at = scheduled_at()
      user = insert(:user, scheduled_deletion: at, disabled: true)

      conn
      |> delete(~p"/api/users/#{user.id}")
      |> assert_problem(409, :scheduled_for_deletion, [])

      assert Repo.reload!(user).scheduled_deletion == at
      assert audits(user.id) == []
    end

    test "answers 409 superuser for a superuser, who can't be deleted, changing nothing",
         %{conn: conn} do
      superuser = insert(:user, role: :superuser)

      conn
      |> delete(~p"/api/users/#{superuser.id}")
      |> assert_problem(409, :superuser, [])

      assert %User{disabled: false, scheduled_deletion: nil} =
               Repo.reload!(superuser)

      assert audits(superuser.id) == []
      refute_email_sent()
    end
  end

  describe "cancelling a user's deletion" do
    test "re-enables the user and answers with them, recorded as the service account",
         %{conn: conn, account: account} do
      user =
        insert(:user,
          first_name: "Ada",
          scheduled_deletion: scheduled_at(),
          disabled: true
        )

      conn = delete(conn, ~p"/api/users/#{user.id}/scheduled_deletion")

      assert json_response(conn, 200) == %{
               "data" => %{
                 "type" => "users",
                 "id" => user.id,
                 "attributes" => %{
                   "email" => user.email,
                   "first_name" => "Ada",
                   "last_name" => user.last_name,
                   "role" => "user"
                 },
                 "links" => %{"self" => user_url(user.id)}
               }
             }

      assert %User{disabled: false, scheduled_deletion: nil} = Repo.reload!(user)

      assert [%{event: "updated", actor_type: :service_account} = audit] =
               audits(user.id)

      assert audit.actor_id == account.uuid
    end

    test "answers 404 not_found for a user who isn't scheduled", %{conn: conn} do
      user = insert(:user)

      conn
      |> delete(~p"/api/users/#{user.id}/scheduled_deletion")
      |> assert_problem(404, :not_found, [])

      assert audits(user.id) == []
    end
  end

  describe "who may reach it" do
    test "the service account hears what is missing or malformed; a person's token or a superuser's gets 403 for every id",
         %{conn: conn} do
      existing =
        insert(:user, scheduled_deletion: scheduled_at(), disabled: true)

      unscheduled = insert(:user)
      superuser = insert(:user, role: :superuser)
      malformed = [not_a_uuid_entry(%{"path" => "id"})]

      paths = fn id ->
        [~p"/api/users/#{id}", ~p"/api/users/#{id}/scheduled_deletion"]
      end

      people =
        for user <- [insert(:user), superuser], do: assign_bearer(conn, user)

      refused =
        for caller <- people,
            id <- [
              existing.id,
              unscheduled.id,
              Ecto.UUID.generate(),
              "not-a-uuid"
            ],
            path <- paths.(id),
            do: {caller, path, 403, :forbidden, []}

      permitted =
        for {id, status, code, entries} <- [
              {Ecto.UUID.generate(), 404, :not_found, []},
              {"not-a-uuid", 400, :invalid_parameter, malformed}
            ],
            path <- paths.(id),
            do: {conn, path, status, code, entries}

      for {caller, path, status, code, entries} <-
            refused ++ permitted do
        caller
        |> put_req_header("accept", "application/json")
        |> delete(path)
        |> assert_problem(status, code, entries)
      end

      assert %User{disabled: true} = Repo.reload!(existing)
      assert Repo.reload!(unscheduled).scheduled_deletion == nil
    end
  end

  describe "stale writes" do
    test "a user another request deletes mid-schedule answers 409 concurrent_edit",
         %{conn: conn} do
      user = insert(:user)

      after_first_query("users", user.id, fn id ->
        Repo.query!("DELETE FROM users WHERE id = $1", [id])
      end)

      conn
      |> delete(~p"/api/users/#{user.id}")
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(user)
      refute_email_sent()
    end

    test "a user another request deletes mid-cancel answers 409 concurrent_edit",
         %{conn: conn} do
      user = insert(:user, scheduled_deletion: scheduled_at(), disabled: true)

      after_first_query("users", user.id, fn id ->
        Repo.query!("DELETE FROM users WHERE id = $1", [id])
      end)

      conn
      |> delete(~p"/api/users/#{user.id}/scheduled_deletion")
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(user)
    end
  end
end
