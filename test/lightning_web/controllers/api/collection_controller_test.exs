defmodule LightningWeb.API.CollectionControllerTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import Lightning.RaceHelpers
  import Ecto.Query
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  alias Lightning.Collections
  alias Lightning.Collections.Collection
  alias Lightning.Repo

  @body_no_route_accepts %{"name" => "Not Safe", "x" => 1}

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp service_account(%{conn: conn}) do
    {conn, account} = with_service_account(conn, ["collections:write"])
    %{conn: conn, account: account, project: insert(:project)}
  end

  defp entry(pointer, code, detail),
    do: %{"pointer" => pointer, "code" => code, "detail" => detail}

  defp scheduled_for_deletion do
    DateTime.utc_now() |> DateTime.truncate(:second)
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

  describe "PUT creates or renames" do
    setup :service_account

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
  end

  describe "PUT refuses the body" do
    setup :service_account

    test "refuses a body it cannot take with one 422, each error at its key", %{
      conn: conn,
      project: project
    } do
      unknown = &entry("#/" <> &1, "unknown_key", "is not accepted")

      blank = entry("#/name", "required", "can't be blank")

      unsafe = entry("#/name", "format", "Collection name must be URL safe")

      refused = [
        unknown_key:
          {%{"name" => "patients", "items" => []}, [unknown.("items")]},
        project_key:
          {%{"name" => "patients", "project_id" => insert(:project).id},
           [unknown.("project_id")]},
        other_id:
          {%{"name" => "patients", "id" => Ecto.UUID.generate()},
           [
             entry("#/id", "mismatch", "does not match the id in the path")
           ]},
        missing_name: {%{}, [blank]},
        blank_name: {%{"name" => ""}, [blank]},
        unsafe_name: {%{"name" => "Not Safe"}, [unsafe]},
        name_not_string:
          {%{"name" => 7}, [entry("#/name", "type", "is invalid")]},
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
        entry("#/id", "mismatch", "does not match the id in the path"),
        entry("#/name", "format", "Collection name must be URL safe")
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

    test "never quotes a value from the request", %{conn: conn, project: project} do
      collection = insert(:collection, project: project, name: "patients")

      for {body, entry} <- [
            {%{"name" => "Not Safe", "id" => "x"},
             %{
               "pointer" => "#/id",
               "code" => "mismatch",
               "detail" => "does not match the id in the path"
             }},
            {%{"name" => "x", "colour" => "x"},
             %{
               "pointer" => "#/colour",
               "code" => "unknown_key",
               "detail" => "is not accepted"
             }},
            {%{"name" => ["x"]},
             %{
               "pointer" => "#/name",
               "code" => "type",
               "detail" => "is invalid"
             }}
          ],
          id <- [Ecto.UUID.generate(), collection.id] do
        conn
        |> put_collection(project.id, id, plant_sentinel(body))
        |> refute_sentinel()
        |> assert_problem(422, :invalid, [entry])
      end
    end
  end

  describe "PUT refuses a name or id already held" do
    setup :service_account

    test "answers 422 invalid with a taken entry at the name when another collection in the project has it",
         %{conn: conn, project: project} do
      insert(:collection, project: project, name: "patients")
      other = insert(:collection, project: project, name: "visits")
      id = Ecto.UUID.generate()

      taken = [
        entry("#/name", "taken", "A collection with this name already exists")
      ]

      created = put_collection(conn, project.id, id, %{"name" => "patients"})
      assert_problem(created, 422, :invalid, taken)
      refute Repo.get(Collection, id)

      renamed =
        put_collection(conn, project.id, other.id, %{"name" => "patients"})

      assert_problem(renamed, 422, :invalid, taken)
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
  end

  describe "PUT refuses a write it cannot land" do
    setup :service_account

    test "a collection another request deletes mid-rename answers 409 concurrent_edit",
         %{conn: conn, project: project} do
      collection = insert(:collection, project: project, name: "patients")

      after_first_query("collections", collection.id, fn id ->
        Repo.query!("DELETE FROM collections WHERE id = $1", [id])
      end)

      conn
      |> put_collection(project.id, collection.id, %{"name" => "people"})
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(collection)
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
        entry("#/name", "required", "can't be blank")
      ])
    end
  end

  describe "reading" do
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

    test "an owner or an admin reads a project's collection", %{conn: conn} do
      for role <- [:owner, :admin] do
        user = insert(:user)
        project = insert(:project, project_users: [%{user: user, role: role}])
        collection = insert(:collection, project: project, name: "patients")

        conn =
          conn
          |> with_pat(user)
          |> get(~p"/api/projects/#{project.id}/collections/#{collection.id}")

        assert json_response(conn, 200) == %{
                 "data" => %{
                   "id" => collection.id,
                   "project_id" => project.id,
                   "name" => "patients"
                 }
               }
      end
    end
  end

  describe "who may reach it" do
    test "a caller the project refuses gets the same 403 for every id, and a permitted caller hears what is missing, malformed or held elsewhere",
         %{conn: conn} do
      [owner, admin, editor, viewer, stranger, short_of_mfa] =
        insert_list(6, :user)

      superuser = insert(:user, role: :superuser)

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

      scheduled = insert(:project, scheduled_deletion: scheduled_for_deletion())

      held_out_of_sight = insert(:collection, name: "hidden")

      held_in_sight =
        insert(:collection,
          name: "visible",
          project:
            insert(:project,
              project_users: [
                %{user: owner, role: :owner},
                %{user: admin, role: :admin},
                %{user: viewer, role: :admin}
              ]
            )
        )

      {service_account, _account} =
        with_service_account(conn, ["collections:write"])

      unknown = Ecto.UUID.generate()
      malformed_id = [not_a_uuid_entry(%{"path" => "id"})]

      refused =
        for {user, project} <- [
              {stranger, project},
              {editor, project},
              {viewer, project},
              {short_of_mfa, mfa_project},
              {stranger, scheduled}
            ],
            {project_id, id} <- [
              {project.id, insert(:collection, project: project).id},
              {project.id, unknown},
              {project.id, "not-a-uuid"},
              {project.id, held_out_of_sight.id},
              {project.id, held_in_sight.id},
              {Ecto.UUID.generate(), unknown},
              {"not-a-uuid", unknown}
            ],
            verb <- [:get, :put],
            do: {with_pat(conn, user), verb, project_id, id, 403, :forbidden, []}

      refused_superuser =
        for id <- [
              insert(:collection, project: project).id,
              unknown,
              "not-a-uuid"
            ],
            verb <- [:get, :put],
            do:
              {with_pat(conn, superuser), verb, project.id, id, 403, :forbidden,
               []}

      permitted =
        for caller <- [
              with_pat(conn, owner),
              with_pat(conn, admin),
              service_account
            ],
            {verb, id, status, code, entries} <- [
              {:get, unknown, 404, :not_found, []},
              {:get, held_out_of_sight.id, 404, :not_found, []},
              {:get, held_in_sight.id, 404, :not_found, []},
              {:get, "not-a-uuid", 400, :invalid_parameter, malformed_id},
              {:put, "not-a-uuid", 400, :invalid_parameter, malformed_id},
              {:put, held_out_of_sight.id, 409, :id_taken, []},
              {:put, held_in_sight.id, 409, :id_taken, []}
            ],
            do: {caller, verb, project.id, id, status, code, entries}

      unknown_project =
        for {caller, status, code, entries} <- [
              {with_pat(conn, owner), 403, :forbidden, []},
              {with_pat(conn, superuser), 404, :not_found, []},
              {service_account, 404, :not_found, []}
            ],
            verb <- [:get, :put],
            do:
              {caller, verb, Ecto.UUID.generate(), unknown, status, code,
               entries}

      malformed_project =
        for {caller, status, code, entries} <- [
              {with_pat(conn, owner), 403, :forbidden, []},
              {with_pat(conn, superuser), 400, :invalid_parameter,
               [not_a_uuid_entry(%{"path" => "project_id"})]},
              {service_account, 400, :invalid_parameter,
               [not_a_uuid_entry(%{"path" => "project_id"})]}
            ],
            verb <- [:get, :put],
            do: {caller, verb, "not-a-uuid", unknown, status, code, entries}

      for {caller, verb, project_id, id, status, code, entries} <-
            refused ++
              refused_superuser ++
              permitted ++ unknown_project ++ malformed_project do
        caller
        |> reach(verb, project_id, id)
        |> assert_problem(status, code, entries)
      end

      refute Repo.get(Collection, unknown)

      for held <- [held_out_of_sight, held_in_sight] do
        assert Map.take(Repo.reload!(held), [:name, :project_id]) ==
                 Map.take(held, [:name, :project_id])

        assert audits(held.id) == []
      end
    end

    test "an owner of a project scheduled for deletion gets 409 writing or reading",
         %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user: user, role: :owner}],
          scheduled_deletion: scheduled_for_deletion()
        )

      collection = insert(:collection, project: project)
      id = Ecto.UUID.generate()
      conn = with_pat(conn, user)

      written = put_collection(conn, project.id, id, %{"name" => "patients"})
      assert_problem(written, 409, :scheduled_for_deletion, [])
      refute Repo.get(Collection, id)

      read =
        get(conn, ~p"/api/projects/#{project.id}/collections/#{collection.id}")

      assert_problem(read, 409, :scheduled_for_deletion, [])
    end
  end

  defp reach(conn, :get, project_id, id),
    do: get(conn, ~p"/api/projects/#{project_id}/collections/#{id}")

  defp reach(conn, :put, project_id, id),
    do: put_collection(conn, project_id, id, @body_no_route_accepts)
end
