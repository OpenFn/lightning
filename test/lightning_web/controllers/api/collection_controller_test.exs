defmodule LightningWeb.API.CollectionControllerTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  alias Lightning.Collections
  alias Lightning.Collections.Collection
  alias Lightning.Repo

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp put_collection(conn, project_id, id, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put(
      ~p"/api/projects/#{project_id}/collections/#{id}",
      Jason.encode!(body)
    )
  end

  defp with_pat(conn, user) do
    assign_bearer(conn, Lightning.Accounts.generate_api_token(user))
  end

  defp audits(collection_id) do
    Repo.all(
      from a in Lightning.Collections.Audit.base_query(),
        where: a.item_id == ^collection_id,
        order_by: a.inserted_at
    )
  end

  describe "PUT, for a service account with collections:write" do
    setup %{conn: conn} do
      {conn, account} = with_service_account(conn, ["collections:write"])
      %{conn: conn, account: account, project: insert(:project)}
    end

    test "creates the collection under the path id, recording the account", %{
      conn: conn,
      account: account,
      project: project
    } do
      id = Ecto.UUID.generate()

      conn = put_collection(conn, project.id, id, %{"name" => "patients"})

      assert json_response(conn, 201) == %{
               "data" => %{
                 "id" => id,
                 "project_id" => project.id,
                 "name" => "patients"
               }
             }

      assert %Collection{project_id: project_id, name: "patients"} =
               Repo.get(Collection, id)

      assert project_id == project.id

      assert [%{event: "created", actor_type: :service_account} = audit] =
               audits(id)

      assert audit.actor_id == account.uuid
    end

    test "re-sending what is stored answers 200 and records nothing", %{
      conn: conn,
      project: project
    } do
      collection = insert(:collection, project: project, name: "patients")

      conn =
        put_collection(conn, project.id, collection.id, %{"name" => "patients"})

      assert json_response(conn, 200)["data"]["name"] == "patients"
      assert audits(collection.id) == []
    end

    test "renames the collection, keeping its items", %{
      conn: conn,
      project: project
    } do
      collection = insert(:collection, project: project, name: "patients")
      insert(:collection_item, collection: collection, key: "k1", value: "v1")

      conn =
        put_collection(conn, project.id, collection.id, %{"name" => "people"})

      assert json_response(conn, 200)["data"] == %{
               "id" => collection.id,
               "project_id" => project.id,
               "name" => "people"
             }

      assert Collections.get(collection, "k1").value == "v1"

      assert [%{event: "updated"} = audit] = audits(collection.id)
      assert audit.changes.after == %{"name" => "people"}
    end

    test "answers name_taken when another collection in the project has the name",
         %{conn: conn, project: project} do
      insert(:collection, project: project, name: "patients")
      other = insert(:collection, project: project, name: "visits")
      id = Ecto.UUID.generate()

      created = put_collection(conn, project.id, id, %{"name" => "patients"})
      assert json_response(created, 409) == %{"error" => "name_taken"}
      refute Repo.get(Collection, id)

      renamed =
        put_collection(conn, project.id, other.id, %{"name" => "patients"})

      assert json_response(renamed, 409) == %{"error" => "name_taken"}
      assert Repo.reload!(other).name == "visits"
    end

    test "answers id_taken for an id held by a collection in another project",
         %{conn: conn, project: project} do
      elsewhere = insert(:collection, name: "patients")

      conn =
        put_collection(conn, project.id, elsewhere.id, %{"name" => "patients"})

      assert json_response(conn, 409) == %{"error" => "id_taken"}
      assert Repo.reload!(elsewhere).project_id != project.id
      assert audits(elsewhere.id) == []
    end

    test "answers exactly 402 exceeds_limit when the hook refuses, writing nothing",
         %{conn: conn, project: project} do
      Mox.expect(
        Lightning.Extensions.MockCollectionHook,
        :handle_create,
        fn %{"project_id" => project_id} ->
          assert project_id == project.id

          {:error, :exceeds_limit,
           %Lightning.Extensions.Message{text: "Upgrade to the PLANTED plan"}}
        end
      )

      id = Ecto.UUID.generate()
      conn = put_collection(conn, project.id, id, %{"name" => "patients"})

      assert json_response(conn, 402) == %{"error" => "exceeds_limit"}
      refute Repo.get(Collection, id)
      assert audits(id) == []
    end

    test "refuses a body it cannot take with 422, flat and under its key", %{
      conn: conn,
      project: project
    } do
      refused = [
        unknown_key: {%{"name" => "patients", "items" => []}, "items"},
        project_key:
          {%{"name" => "patients", "project_id" => insert(:project).id},
           "project_id"},
        other_id: {%{"name" => "patients", "id" => Ecto.UUID.generate()}, "id"},
        missing_name: {%{}, "name"},
        blank_name: {%{"name" => ""}, "name"},
        unsafe_name: {%{"name" => "Not Safe"}, "name"},
        name_not_string: {%{"name" => 7}, "name"}
      ]

      for {case_name, {body, key}} <- refused do
        id = Ecto.UUID.generate()

        response =
          conn |> put_collection(project.id, id, body) |> json_response(422)

        assert %{"errors" => %{^key => [_ | _] = messages} = errors} = response,
               "#{case_name}: #{inspect(response)}"

        assert map_size(errors) == 1 and Enum.all?(messages, &is_binary/1),
               "#{case_name}: #{inspect(response)}"

        refute Repo.get(Collection, id), "#{case_name} created a collection"
      end

      for path_id <- ["not-a-uuid", "abcdefghijklmnop"] do
        assert %{"errors" => %{"id" => [_]}} =
                 conn
                 |> put_collection(project.id, path_id, %{"name" => "patients"})
                 |> json_response(422),
               path_id
      end
    end

    test "never quotes a submitted value in a 422", %{
      conn: conn,
      project: project
    } do
      planted = "PLANTED-VALUE"

      for body <- [
            %{"name" => planted <> "\u0007"},
            %{"name" => String.duplicate(planted, 10) <> " "},
            %{"name" => "ok", "id" => planted}
          ] do
        conn = put_collection(conn, project.id, Ecto.UUID.generate(), body)

        assert %{"errors" => errors} = json_response(conn, 422)
        assert errors != %{}
        refute conn.resp_body =~ planted
      end
    end

    test "answers 404 for a project that does not exist", %{conn: conn} do
      for project_id <- [Ecto.UUID.generate(), "not-a-uuid"] do
        conn =
          put_collection(conn, project_id, Ecto.UUID.generate(), %{
            "name" => "patients"
          })

        assert json_response(conn, 404)
      end
    end

    test "answers scheduled_for_deletion for a project about to be deleted", %{
      conn: conn
    } do
      project =
        insert(:project,
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      id = Ecto.UUID.generate()
      conn = put_collection(conn, project.id, id, %{"name" => "patients"})

      assert json_response(conn, 409) == %{"error" => "scheduled_for_deletion"}
      refute Repo.get(Collection, id)
    end
  end

  describe "for a service account without collections:write" do
    test "PUT and GET are refused for insufficient scope", %{conn: conn} do
      {conn, _account} = with_service_account(conn, ["projects:write"])
      collection = insert(:collection)

      for refused <- [
            put_collection(conn, collection.project_id, Ecto.UUID.generate(), %{
              "name" => "patients"
            }),
            get(
              conn,
              ~p"/api/projects/#{collection.project_id}/collections/#{collection.id}"
            )
          ] do
        assert json_response(refused, 403) == %{"error" => "insufficient_scope"}
      end
    end
  end

  describe "PUT, for a person's token" do
    test "an owner or admin creates and renames, recorded as the actor", %{
      conn: conn
    } do
      for role <- [:owner, :admin] do
        user = insert(:user)
        project = insert(:project, project_users: [%{user: user, role: role}])
        id = Ecto.UUID.generate()
        conn = with_pat(conn, user)

        assert json_response(
                 put_collection(conn, project.id, id, %{"name" => "patients"}),
                 201
               )

        assert json_response(
                 put_collection(conn, project.id, id, %{"name" => "people"}),
                 200
               )

        assert [
                 %{event: "created", actor_type: :user} = created,
                 %{event: "updated", actor_type: :user} = updated
               ] = audits(id)

        assert created.actor_id == user.id and updated.actor_id == user.id
      end
    end

    test "an editor, a viewer or an outsider is refused with 403", %{
      conn: conn
    } do
      outsider = insert(:user)

      for role <- [:editor, :viewer, nil] do
        user = if role, do: insert(:user), else: outsider

        project_users = if role, do: [%{user: user, role: role}], else: []
        project = insert(:project, project_users: project_users)
        id = Ecto.UUID.generate()

        conn =
          conn
          |> with_pat(user)
          |> put_collection(project.id, id, %{"name" => "patients"})

        assert json_response(conn, 403) == %{"error" => "Forbidden"}
        refute Repo.get(Collection, id)
      end
    end

    test "is refused with 403 on a project scheduled for deletion", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user: user, role: :owner}],
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      conn =
        conn
        |> with_pat(user)
        |> put_collection(project.id, Ecto.UUID.generate(), %{
          "name" => "patients"
        })

      assert json_response(conn, 403) == %{"error" => "Forbidden"}
    end
  end

  describe "GET" do
    test "a service account with the scope reads a project's collection", %{
      conn: conn
    } do
      {conn, _account} = with_service_account(conn, ["collections:write"])
      collection = insert(:collection, name: "patients")

      conn =
        get(
          conn,
          ~p"/api/projects/#{collection.project_id}/collections/#{collection.id}"
        )

      assert json_response(conn, 200) == %{
               "data" => %{
                 "id" => collection.id,
                 "project_id" => collection.project_id,
                 "name" => "patients"
               }
             }
    end

    test "answers 404 for a collection of another project or none", %{
      conn: conn
    } do
      {conn, _account} = with_service_account(conn, ["collections:write"])
      project = insert(:project)
      elsewhere = insert(:collection)

      for id <- [elsewhere.id, Ecto.UUID.generate(), "not-a-uuid"] do
        conn = get(conn, ~p"/api/projects/#{project.id}/collections/#{id}")
        assert json_response(conn, 404)
      end
    end

    test "a person needs :manage_collection on the project", %{conn: conn} do
      admin = insert(:user)
      editor = insert(:user)

      project =
        insert(:project,
          project_users: [
            %{user: admin, role: :admin},
            %{user: editor, role: :editor}
          ]
        )

      collection = insert(:collection, project: project)
      path = ~p"/api/projects/#{project.id}/collections/#{collection.id}"

      assert json_response(conn |> with_pat(admin) |> get(path), 200)

      assert json_response(conn |> with_pat(editor) |> get(path), 403) ==
               %{"error" => "Forbidden"}
    end
  end

  describe "for a repo connection" do
    test "PUT and GET are refused with 403", %{conn: conn} do
      project = insert(:project)
      collection = insert(:collection, project: project)
      repo_connection = insert(:project_repo_connection, project: project)

      conn =
        put_req_header(
          conn,
          "authorization",
          "Bearer " <> repo_connection.access_token
        )

      for refused <- [
            put_collection(conn, project.id, Ecto.UUID.generate(), %{
              "name" => "patients"
            }),
            get(
              conn,
              ~p"/api/projects/#{project.id}/collections/#{collection.id}"
            )
          ] do
        assert json_response(refused, 403) == %{"error" => "Forbidden"}
      end
    end
  end
end
