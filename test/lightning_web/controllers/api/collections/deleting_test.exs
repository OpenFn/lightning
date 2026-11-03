defmodule LightningWeb.API.Collections.DeletingTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import Lightning.RaceHelpers
  import Lightning.ServiceAccountHelpers

  alias Lightning.Collections.Collection
  alias Lightning.Collections.Item
  alias Lightning.Repo

  defp audits(collection_id) do
    Repo.all(
      from a in Lightning.Collections.Audit.base_query(),
        where: a.item_id == ^collection_id
    )
  end

  defp delete_collection(conn, project_id, id),
    do: delete(conn, ~p"/api/projects/#{project_id}/collections/#{id}")

  describe "deleting" do
    test "an owner on Lightning's own app deletes a collection and its items, recorded as the actor",
         %{conn: conn} do
      owner = insert(:user)
      project = insert(:project, project_users: [%{user: owner, role: :owner}])
      collection = insert(:collection, project: project, name: "patients")
      insert(:collection_item, collection: collection, key: "k", value: "v")

      conn =
        conn
        |> session_conn(owner)
        |> delete_collection(project.id, collection.id)

      assert response(conn, 204) == ""
      refute Repo.reload(collection)

      assert Repo.all(from i in Item, where: i.collection_id == ^collection.id) ==
               []

      assert [%{event: "deleted", actor_type: :user} = audit] =
               audits(collection.id)

      assert audit.actor_id == owner.id

      assert audit.changes.before == %{
               "name" => "patients",
               "project_id" => project.id
             }
    end

    test "a service account with collections:write deletes one, recorded as the account",
         %{conn: conn} do
      {conn, account} = with_service_account(conn, ["collections:write"])
      collection = insert(:collection)

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> delete_collection(collection.project_id, collection.id)

      assert response(conn, 204) == ""
      refute Repo.reload(collection)

      assert [%{event: "deleted", actor_type: :service_account} = audit] =
               audits(collection.id)

      assert audit.actor_id == account.uuid
    end
  end

  describe "stale writes" do
    test "a collection another request deletes mid-delete answers 409 concurrent_edit",
         %{conn: conn} do
      owner = insert(:user)
      project = insert(:project, project_users: [%{user: owner, role: :owner}])
      collection = insert(:collection, project: project)

      after_first_query("collections", collection.id, fn id ->
        Repo.query!("DELETE FROM collections WHERE id = $1", [id])
      end)

      conn
      |> session_conn(owner)
      |> delete_collection(project.id, collection.id)
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(collection)
      assert audits(collection.id) == []
    end
  end

  describe "who may reach it" do
    test "a caller the project refuses gets the same 403 for every id, and a permitted caller hears what is missing or malformed",
         %{conn: conn} do
      [owner, admin, editor, viewer, stranger, short_of_mfa] =
        insert_list(6, :user)

      project =
        insert(:project,
          project_users: [
            %{user: owner, role: :owner},
            %{user: admin, role: :admin},
            %{user: editor, role: :editor},
            %{user: viewer, role: :viewer}
          ]
        )

      mfa_project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: short_of_mfa, role: :owner}]
        )

      kept = insert(:collection, project: project)
      kept_mfa = insert(:collection, project: mfa_project)
      elsewhere = insert(:collection)

      {service_account, _account} =
        with_service_account(conn, ["collections:write"])

      service_account =
        put_req_header(service_account, "accept", "application/json")

      malformed = [not_a_uuid_entry(%{"path" => "id"})]

      refused =
        for {user, project, collection} <- [
              {stranger, project, kept},
              {editor, project, kept},
              {viewer, project, kept},
              {insert(:user, role: :superuser), project, kept},
              {short_of_mfa, mfa_project, kept_mfa}
            ],
            id <- [collection.id, Ecto.UUID.generate(), "not-a-uuid"],
            do: {session_conn(conn, user), project.id, id, 403, :forbidden, []}

      permitted =
        for caller <- [
              session_conn(conn, owner),
              session_conn(conn, admin),
              service_account
            ],
            {id, status, code, entries} <- [
              {Ecto.UUID.generate(), 404, :not_found, []},
              {elsewhere.id, 404, :not_found, []},
              {"not-a-uuid", 400, :invalid_parameter, malformed}
            ],
            do: {caller, project.id, id, status, code, entries}

      for {caller, project_id, id, status, code, entries} <-
            refused ++ permitted do
        caller
        |> delete_collection(project_id, id)
        |> assert_problem(status, code, entries)
      end

      for collection <- [kept, kept_mfa, elsewhere],
          do: assert(Repo.get(Collection, collection.id))
    end

    test "an owner of a project scheduled for deletion gets 409, and the collection stays",
         %{conn: conn} do
      owner = insert(:user)

      project =
        insert(:project,
          project_users: [%{user: owner, role: :owner}],
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      collection = insert(:collection, project: project)

      conn
      |> session_conn(owner)
      |> delete_collection(project.id, collection.id)
      |> assert_problem(409, :scheduled_for_deletion, [])

      assert Repo.reload(collection)
    end
  end
end
