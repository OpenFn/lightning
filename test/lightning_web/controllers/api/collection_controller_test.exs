defmodule LightningWeb.API.CollectionControllerTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
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

    test "answers 409 taken at the name when another collection in the project has it",
         %{conn: conn, project: project} do
      insert(:collection, project: project, name: "patients")
      other = insert(:collection, project: project, name: "visits")
      id = Ecto.UUID.generate()

      taken = [
        %{
          "pointer" => "#/name",
          "code" => "taken",
          "detail" => "A collection with this name already exists"
        }
      ]

      created = put_collection(conn, project.id, id, %{"name" => "patients"})
      assert_problem(created, 409, :taken, taken)
      refute Repo.get(Collection, id)

      renamed =
        put_collection(conn, project.id, other.id, %{"name" => "patients"})

      assert_problem(renamed, 409, :taken, taken)
      assert Repo.reload!(other).name == "visits"
    end

    test "answers 409 id_taken for an id held by a collection in another project, whatever the body",
         %{conn: conn, project: project} do
      elsewhere = insert(:collection, name: "patients")

      for body <- [%{"name" => "patients"}, %{"name" => "Not Safe", "x" => 1}] do
        conn = put_collection(conn, project.id, elsewhere.id, body)
        assert_problem(conn, 409, :id_taken, [])
      end

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

      assert_problem(conn, 402, :exceeds_limit, [])
      refute Repo.get(Collection, id)
      assert audits(id) == []
    end

    test "refuses a body it cannot take with one 422, each error at its key", %{
      conn: conn,
      project: project
    } do
      unknown =
        &%{
          "pointer" => "#/" <> &1,
          "code" => "unknown_key",
          "detail" => "is not accepted"
        }

      blank = %{
        "pointer" => "#/name",
        "code" => "required",
        "detail" => "can't be blank"
      }

      unsafe = %{
        "pointer" => "#/name",
        "code" => "format",
        "detail" => "Collection name must be URL safe"
      }

      refused = [
        unknown_key:
          {%{"name" => "patients", "items" => []}, [unknown.("items")]},
        project_key:
          {%{"name" => "patients", "project_id" => insert(:project).id},
           [unknown.("project_id")]},
        other_id:
          {%{"name" => "patients", "id" => Ecto.UUID.generate()},
           [
             %{
               "pointer" => "#/id",
               "code" => "mismatch",
               "detail" => "does not match the id in the path"
             }
           ]},
        missing_name: {%{}, [blank]},
        blank_name: {%{"name" => ""}, [blank]},
        unsafe_name: {%{"name" => "Not Safe"}, [unsafe]},
        name_not_string:
          {%{"name" => 7},
           [%{"pointer" => "#/name", "code" => "type", "detail" => "is invalid"}]},
        all_at_once:
          {%{"name" => "Not Safe", "colour" => "red"},
           [unknown.("colour"), unsafe]}
      ]

      for {case_name, {body, entries}} <- refused do
        id = Ecto.UUID.generate()
        conn = put_collection(conn, project.id, id, body)

        assert conn.status == 422, "#{case_name}: #{conn.resp_body}"
        assert_problem(conn, 422, :invalid, entries)
        refute Repo.get(Collection, id), "#{case_name} created a collection"
      end
    end

    test "refuses a renaming body the same way, leaving the name", %{
      conn: conn,
      project: project
    } do
      collection = insert(:collection, project: project, name: "patients")

      conn =
        put_collection(conn, project.id, collection.id, %{
          "name" => "Not Safe",
          "id" => Ecto.UUID.generate()
        })

      assert_problem(conn, 422, :invalid, [
        %{
          "pointer" => "#/id",
          "code" => "mismatch",
          "detail" => "does not match the id in the path"
        },
        %{
          "pointer" => "#/name",
          "code" => "format",
          "detail" => "Collection name must be URL safe"
        }
      ])

      assert Repo.reload!(collection).name == "patients"
    end

    test "answers 400 malformed for a body that is not a JSON object", %{
      conn: conn,
      project: project
    } do
      for body <- [["patients"], "patients", 7] do
        id = Ecto.UUID.generate()
        conn = put_collection(conn, project.id, id, body)

        assert_problem(conn, 400, :malformed, [])
        refute Repo.get(Collection, id)
      end
    end

    test "answers 422 rather than 402 for a refused body, when the plan limit is also reached",
         %{conn: conn, project: project} do
      Mox.stub(
        Lightning.Extensions.MockCollectionHook,
        :handle_create,
        fn _attrs ->
          {:error, :exceeds_limit, %Lightning.Extensions.Message{text: "full"}}
        end
      )

      conn = put_collection(conn, project.id, Ecto.UUID.generate(), %{})

      assert_problem(conn, 422, :invalid, [
        %{
          "pointer" => "#/name",
          "code" => "required",
          "detail" => "can't be blank"
        }
      ])
    end

    test "answers 404 for a path id that is not a UUID", %{
      conn: conn,
      project: project
    } do
      for path_id <- ["not-a-uuid", "abcdefghijklmnop"] do
        conn = put_collection(conn, project.id, path_id, %{"name" => "patients"})
        assert_problem(conn, 404, :not_found, [])
      end
    end

    test "never quotes a value from the request, on any route", %{
      conn: conn,
      project: project
    } do
      collection = insert(:collection, project: project, name: "patients")

      for body <- [
            %{"name" => "Not Safe", "id" => "x"},
            %{"name" => "x", "colour" => "x"},
            %{"name" => ["x"]}
          ],
          id <- [Ecto.UUID.generate(), collection.id] do
        conn
        |> put_collection(project.id, id, plant_sentinel(body))
        |> refute_sentinel()
        |> assert_problem(422, :invalid)
      end

      sentinel = plant_sentinel(%{"v" => "x"})["v"]

      for project_id <- [project.id, sentinel] do
        conn
        |> put_collection(project_id, sentinel, %{"name" => "patients"})
        |> refute_sentinel()
        |> assert_problem(404, :not_found, [])

        conn
        |> get(~p"/api/projects/#{project_id}/collections/#{sentinel}")
        |> refute_sentinel()
        |> assert_problem(404, :not_found, [])
      end
    end

    test "answers 404 for a project that does not exist", %{conn: conn} do
      for project_id <- [Ecto.UUID.generate(), "not-a-uuid"] do
        conn =
          put_collection(conn, project_id, Ecto.UUID.generate(), %{
            "name" => "patients"
          })

        assert_problem(conn, 404, :not_found, [])
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

      assert_problem(conn, 409, :scheduled_for_deletion, [])
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
        assert_problem(refused, 403, :insufficient_scope)

        assert get_resp_header(refused, "www-authenticate") == [
                 ~s(Bearer error="insufficient_scope", scope="collections:write")
               ]
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

        assert_problem(conn, 403, :forbidden, [])
        refute Repo.get(Collection, id)
      end
    end

    test "is refused with 403 for a non-member on a project scheduled for deletion",
         %{conn: conn} do
      outsider = insert(:user)

      project =
        insert(:project,
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      conn =
        conn
        |> with_pat(outsider)
        |> put_collection(project.id, Ecto.UUID.generate(), %{
          "name" => "patients"
        })

      assert_problem(conn, 403, :forbidden, [])
    end

    test "the owner gets 409 on a project scheduled for deletion", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user: user, role: :owner}],
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      id = Ecto.UUID.generate()

      conn =
        conn
        |> with_pat(user)
        |> put_collection(project.id, id, %{"name" => "patients"})

      assert_problem(conn, 409, :scheduled_for_deletion, [])
      refute Repo.get(Collection, id)
    end

    test "the owner gets 409 reading a collection on a project scheduled for deletion",
         %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user: user, role: :owner}],
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      collection = insert(:collection, project: project)

      conn =
        conn
        |> with_pat(user)
        |> get(~p"/api/projects/#{project.id}/collections/#{collection.id}")

      assert_problem(conn, 409, :scheduled_for_deletion, [])
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
        assert_problem(conn, 404, :not_found, [])
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

      assert_problem(conn |> with_pat(editor) |> get(path), 403, :forbidden, [])
    end
  end

  describe "for a repo connection" do
    test "PUT and GET are refused with 403 for not holding collections:write", %{
      conn: conn
    } do
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
        assert_problem(refused, 403, :insufficient_scope)

        assert get_resp_header(refused, "www-authenticate") == [
                 ~s(Bearer error="insufficient_scope", scope="collections:write")
               ]
      end
    end
  end
end
