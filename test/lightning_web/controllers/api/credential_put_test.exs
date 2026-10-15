defmodule LightningWeb.API.CredentialPutTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import Lightning.AdaptorTestHelpers
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers
  import Ecto.Query

  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Repo

  @secret "s3cr3t-never-rendered"

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp put_credential(conn, id, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put(~p"/api/credentials/#{id}", Jason.encode!(body))
  end

  defp with_pat(conn, user) do
    assign_bearer(conn, Lightning.Accounts.generate_api_token(user))
  end

  defp credential_body(attrs) do
    Map.merge(
      %{
        "name" => "Acme DHIS2",
        "schema" => "raw",
        "credential_bodies" => [
          %{"name" => "main", "body" => %{"password" => @secret}}
        ]
      },
      attrs
    )
  end

  defp links(project_ids),
    do: Enum.map(project_ids, &%{"project_id" => &1})

  defp main_body(credential_id),
    do: Credentials.get_credential_body(credential_id, "main").body

  defp linked_project_ids(response) do
    response["credential"]["project_credentials"]
    |> Enum.map(& &1["project_id"])
    |> Enum.sort()
  end

  # A credential with a staging body beside its main one, linked to `project`.
  # Inserted directly, so the owner needn't have access to `project`.
  defp existing_credential(owner, project) do
    insert(:credential,
      name: "Acme DHIS2",
      schema: "raw",
      user: owner,
      project_credentials: [%{project_id: project.id}]
    )
    |> with_body(%{name: "main", body: %{"password" => "old"}})
    |> with_body(%{name: "staging", body: %{"password" => "staging"}})
  end

  defp scheduled_for_deletion(credential) do
    credential
    |> Ecto.Changeset.change(
      scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update!()
  end

  defp count_queries(fun) do
    parent = self()
    ref = make_ref()
    handler = "count-queries-#{inspect(ref)}"

    :telemetry.attach(
      handler,
      [:lightning, :repo, :query],
      fn _event, _measurements, _meta, _config ->
        if self() == parent, do: send(parent, {ref, :query})
      end,
      nil
    )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    Stream.repeatedly(fn ->
      receive do
        {^ref, :query} -> :query
      after
        0 -> :done
      end
    end)
    |> Enum.take_while(&(&1 == :query))
    |> length()
  end

  defp audit_ids(credential_id) do
    Repo.all(
      from a in Lightning.Credentials.Audit.base_query(),
        where: a.item_id == ^credential_id,
        select: a.id
    )
  end

  describe "PUT, for a service account with credentials:write" do
    setup %{conn: conn} do
      {conn, account} = with_service_account(conn, ["credentials:write"])
      %{conn: conn, account: account}
    end

    test "creates the credential under the path id for the owner it names", %{
      conn: conn
    } do
      owner = insert(:user, email: "alice@example.com")

      [project_a, project_b] =
        insert_pair(:project, project_users: [%{user: owner}])

      id = Ecto.UUID.generate()

      conn =
        put_credential(
          conn,
          id,
          credential_body(%{
            "owner" => "ALICE@example.com",
            "project_credentials" => links([project_a.id, project_b.id])
          })
        )

      response = json_response(conn, 201)

      # Without projects:write the account sees the links, but no project
      # names.
      assert %{
               "credential" => %{
                 "id" => ^id,
                 "name" => "Acme DHIS2",
                 "schema" => "raw",
                 "user_id" => user_id,
                 "projects" => []
               },
               "errors" => %{}
             } = response

      assert user_id == owner.id

      assert linked_project_ids(response) ==
               Enum.sort([project_a.id, project_b.id])

      refute conn.resp_body =~ @secret
      assert main_body(id) == %{"password" => @secret}
    end

    test "replaces name, schema and main body; keeps other bodies and every link",
         %{conn: conn} do
      owner = insert(:user)
      earlier = insert(:project)
      requested = insert(:project, project_users: [%{user: owner}])
      credential = existing_credential(owner, earlier)

      conn =
        put_credential(
          conn,
          credential.id,
          credential_body(%{
            "name" => "Renamed",
            "owner" => owner.email,
            "credential_bodies" => [
              %{"name" => "main", "body" => %{"password" => @secret}}
            ],
            "project_credentials" => links([requested.id])
          })
        )

      response = json_response(conn, 200)

      assert response["credential"]["name"] == "Renamed"

      assert linked_project_ids(response) ==
               Enum.sort([earlier.id, requested.id])

      [earlier_link] =
        Enum.filter(
          response["credential"]["project_credentials"],
          &(&1["project_id"] == earlier.id)
        )

      assert earlier_link["id"] ==
               Repo.get_by!(Lightning.Projects.ProjectCredential,
                 project_id: earlier.id,
                 credential_id: credential.id
               ).id

      refute conn.resp_body =~ @secret
      assert main_body(credential.id) == %{"password" => @secret}

      assert Credentials.get_credential_body(credential.id, "staging").body ==
               %{"password" => "staging"}
    end

    test "re-sending what is stored answers 200 and changes nothing", %{
      conn: conn
    } do
      owner = insert(:user)
      project = insert(:project, project_users: [%{user: owner}])
      id = Ecto.UUID.generate()

      body =
        credential_body(%{
          "owner" => owner.email,
          "project_credentials" => links([project.id])
        })

      first = conn |> put_credential(id, body) |> json_response(201)
      second = conn |> put_credential(id, body) |> json_response(200)

      assert second["credential"]["project_credentials"] ==
               first["credential"]["project_credentials"]
    end

    test "will not rewrite another owner's credential through a new owner", %{
      conn: conn
    } do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))
      other = insert(:user)

      conn =
        put_credential(
          conn,
          credential.id,
          credential_body(%{"name" => "Hijacked", "owner" => other.email})
        )

      assert_problem(conn, 409, :id_taken, [])

      assert %Credential{name: "Acme DHIS2", user_id: owner_id} =
               Repo.reload!(credential)

      assert owner_id == owner.id
      assert main_body(credential.id) == %{"password" => "old"}
    end

    test "answers scheduled_for_deletion and writes nothing to a credential being deleted",
         %{conn: conn} do
      owner = insert(:user)
      [earlier, requested] = insert_pair(:project)
      credential = scheduled_for_deletion(existing_credential(owner, earlier))
      audits_before = audit_ids(credential.id)

      conn =
        put_credential(
          conn,
          credential.id,
          credential_body(%{
            "name" => "Renamed",
            "owner" => owner.email,
            "project_credentials" => links([requested.id])
          })
        )

      assert_problem(conn, 409, :scheduled_for_deletion, [])
      assert Repo.reload!(credential).name == "Acme DHIS2"
      assert main_body(credential.id) == %{"password" => "old"}

      assert Repo.all(
               from pc in Lightning.Projects.ProjectCredential,
                 where: pc.credential_id == ^credential.id,
                 select: pc.project_id
             ) == [earlier.id]

      assert audit_ids(credential.id) == audits_before
    end

    test "answers 409 taken when the owner holds the name under another id",
         %{conn: conn} do
      owner = insert(:user)
      held = insert(:credential, user: owner, name: "Taken")
      renamed = insert(:credential, user: owner, name: "Mine")
      new_id = Ecto.UUID.generate()

      created =
        put_credential(
          conn,
          new_id,
          credential_body(%{"name" => "Taken", "owner" => owner.email})
        )

      assert_problem(created, 409, :taken, [
        %{
          "pointer" => "#/name",
          "code" => "taken",
          "detail" => "you have another credential with the same name"
        }
      ])

      refute Repo.get(Credential, new_id)

      replaced =
        put_credential(
          conn,
          renamed.id,
          credential_body(%{"name" => held.name, "owner" => owner.email})
        )

      assert_problem(replaced, 409, :taken, [
        %{
          "pointer" => "#/name",
          "code" => "taken",
          "detail" => "you have another credential with the same name"
        }
      ])

      assert Repo.reload!(renamed).name == "Mine"
    end

    test "refuses a body it cannot take with 422, at each key it refuses", %{
      conn: conn
    } do
      owner = insert(:user)
      project_id = insert(:project).id
      main = %{"name" => "main", "body" => %{"a" => "b"}}

      entry = fn pointer, code, detail ->
        %{"pointer" => pointer, "code" => code, "detail" => detail}
      end

      one_body =
        entry.(
          "#/credential_bodies",
          "one_body",
          "must be one body named main, holding an object"
        )

      refused = [
        unknown_key:
          {%{"external_id" => "x"},
           [entry.("#/external_id", "unknown_key", "is not accepted")]},
        no_bodies: {%{"credential_bodies" => []}, [one_body]},
        missing_bodies: {%{"credential_bodies" => nil}, [one_body]},
        two_bodies:
          {%{"credential_bodies" => [main, %{main | "name" => "staging"}]},
           [one_body]},
        not_main:
          {%{"credential_bodies" => [%{main | "name" => "staging"}]}, [one_body]},
        body_not_object:
          {%{"credential_bodies" => [%{main | "body" => "text"}]}, [one_body]},
        bodies_not_list: {%{"credential_bodies" => main}, [one_body]},
        link_without_project:
          {%{"project_credentials" => [%{"id" => project_id}]},
           [
             entry.(
               "#/project_credentials/0/project_id",
               "required",
               "can't be blank"
             ),
             entry.(
               "#/project_credentials/0/id",
               "unknown_key",
               "is not accepted"
             )
           ]},
        link_not_uuid:
          {%{"project_credentials" => [%{"project_id" => "acme"}]},
           [
             entry.(
               "#/project_credentials/0/project_id",
               "not_found",
               "names nothing you can see"
             )
           ]},
        links_not_list:
          {%{"project_credentials" => %{"project_id" => project_id}},
           [entry.("#/project_credentials", "type", "is invalid")]},
        unknown_owner:
          {%{"owner" => "nobody@example.com"},
           [entry.("#/owner", "not_found", "names nothing you can see")]},
        missing_owner:
          {%{"owner" => nil}, [entry.("#/owner", "required", "can't be blank")]},
        other_id:
          {%{"id" => Ecto.UUID.generate()},
           [
             entry.("#/id", "mismatch", "does not match the id in the path")
           ]},
        blank_name:
          {%{"name" => ""}, [entry.("#/name", "required", "can't be blank")]},
        missing_schema:
          {%{"schema" => nil},
           [entry.("#/schema", "required", "can't be blank")]}
      ]

      for {case_name, {overrides, entries}} <- refused do
        id = Ecto.UUID.generate()

        body =
          %{"owner" => owner.email}
          |> credential_body()
          |> Map.merge(overrides)
          |> Map.reject(fn {_key, value} -> is_nil(value) end)

        conn
        |> put_credential(id, body)
        |> assert_problem(422, :invalid, entries)

        refute Repo.get(Credential, id), "#{case_name} created a credential"
      end
    end

    test "answers 404 for a path id that isn't a written-out UUID", %{
      conn: conn
    } do
      owner = insert(:user)

      for path_id <- ["not-a-uuid", "abcdefghijklmnop"] do
        conn
        |> put_credential(path_id, credential_body(%{"owner" => owner.email}))
        |> assert_problem(404, :not_found, [])
      end
    end

    test "reports every refused key, link and owner in one answer, links by their position in the request",
         %{conn: conn} do
      owner = insert(:user)
      held = insert(:project, project_users: [%{user: owner, role: :owner}])
      member = insert(:project, project_users: [%{user: owner, role: :editor}])
      elsewhere = insert(:project)

      credential =
        insert(:credential,
          name: "Acme DHIS2",
          schema: "raw",
          user: owner,
          project_credentials: [%{project_id: held.id}]
        )

      body =
        credential_body(%{
          "owner" => owner.email,
          "colour" => "blue",
          "credential_bodies" => [],
          "project_credentials" =>
            links([
              member.id,
              elsewhere.id,
              held.id,
              Ecto.UUID.generate()
            ])
        })

      conn
      |> put_credential(credential.id, body)
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/colour",
          "code" => "unknown_key",
          "detail" => "is not accepted"
        },
        %{
          "pointer" => "#/credential_bodies",
          "code" => "one_body",
          "detail" => "must be one body named main, holding an object"
        },
        %{
          "pointer" => "#/project_credentials/1/project_id",
          "code" => "no_access",
          "detail" => "the credential's owner is not a member of this project"
        },
        %{
          "pointer" => "#/project_credentials/3/project_id",
          "code" => "not_found",
          "detail" => "names nothing you can see"
        }
      ])

      assert Repo.all(
               from pc in Lightning.Projects.ProjectCredential,
                 where: pc.credential_id == ^credential.id,
                 select: pc.project_id
             ) == [held.id]
    end

    test "never quotes a submitted value in a 422", %{conn: conn} do
      owner = insert(:user)
      planted = "PLANTED-VALUE"

      bodies = [
        %{
          "owner" => owner.email,
          "name" => planted <> "\u0007",
          "schema" => String.duplicate(planted, 10)
        },
        %{"owner" => planted <> "@example.com"},
        %{
          "owner" => owner.email,
          "credential_bodies" => [%{"name" => planted, "body" => planted}],
          "project_credentials" => [%{"project_id" => planted}]
        }
      ]

      for overrides <- bodies do
        conn =
          put_credential(conn, Ecto.UUID.generate(), credential_body(overrides))

        assert %{"errors" => [_ | _]} = assert_problem(conn, 422, :invalid)
        refute conn.resp_body =~ planted
      end
    end

    test "refuses with 422 a link to a project the owner has no access to", %{
      conn: conn
    } do
      owner = insert(:user)
      elsewhere = insert(:project)
      id = Ecto.UUID.generate()

      conn =
        put_credential(
          conn,
          id,
          credential_body(%{
            "owner" => owner.email,
            "project_credentials" => links([elsewhere.id])
          })
        )

      assert_problem(conn, 422, :invalid, [
        %{
          "pointer" => "#/project_credentials/0/project_id",
          "code" => "no_access",
          "detail" => "the credential's owner is not a member of this project"
        }
      ])

      refute Repo.get(Credential, id)
    end

    test "links a support user's credential to a project allowing support access",
         %{conn: conn} do
      owner = insert(:user, support_user: true)
      project = insert(:project, allow_support_access: true)
      id = Ecto.UUID.generate()

      conn =
        put_credential(
          conn,
          id,
          credential_body(%{
            "owner" => owner.email,
            "project_credentials" => links([project.id])
          })
        )

      assert linked_project_ids(json_response(conn, 201)) == [project.id]
    end

    test "refuses a listed project that does not exist as naming nothing", %{
      conn: conn
    } do
      owner = insert(:user)
      id = Ecto.UUID.generate()

      conn =
        put_credential(
          conn,
          id,
          credential_body(%{
            "owner" => owner.email,
            "project_credentials" => links([Ecto.UUID.generate()])
          })
        )

      assert_problem(conn, 422, :invalid, [
        %{
          "pointer" => "#/project_credentials/0/project_id",
          "code" => "not_found",
          "detail" => "names nothing you can see"
        }
      ])

      refute Repo.get(Credential, id)
    end
  end

  describe "for a service account without credentials:write" do
    test "PUT and GET are refused for insufficient scope", %{conn: conn} do
      {conn, _account} = with_service_account(conn, ["projects:write"])
      owner = insert(:user)
      credential = insert(:credential, user: owner)

      for refused <- [
            put_credential(
              conn,
              Ecto.UUID.generate(),
              credential_body(%{"owner" => owner.email})
            ),
            get(conn, ~p"/api/credentials/#{credential.id}")
          ] do
        assert_problem(refused, 403, :insufficient_scope)

        assert get_resp_header(refused, "www-authenticate") == [
                 ~s(Bearer error="insufficient_scope", scope="credentials:write")
               ]
      end
    end
  end

  describe "PUT, for a person's token" do
    test "creates a credential they own without naming an owner", %{conn: conn} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user, role: :editor}])
      id = Ecto.UUID.generate()

      response =
        conn
        |> with_pat(user)
        |> put_credential(
          id,
          credential_body(%{"project_credentials" => links([project.id])})
        )
        |> json_response(201)

      assert response["credential"]["user_id"] == user.id
      assert linked_project_ids(response) == [project.id]
    end

    test "may name themselves as owner, but no one else", %{conn: conn} do
      user = insert(:user)
      other = insert(:user)
      conn = with_pat(conn, user)

      assert conn
             |> put_credential(
               Ecto.UUID.generate(),
               credential_body(%{"owner" => String.upcase(user.email)})
             )
             |> json_response(201)

      id = Ecto.UUID.generate()

      conn
      |> put_credential(id, credential_body(%{"owner" => other.email}))
      |> assert_problem(403, :forbidden, [])

      conn
      |> put_credential(
        id,
        credential_body(%{"owner" => "nobody@example.com"})
      )
      |> assert_problem(403, :forbidden, [])

      refute Repo.get(Credential, id)
    end

    test "cannot rewrite a credential someone else owns", %{conn: conn} do
      credential = insert(:credential, user: insert(:user), name: "Theirs")

      conn =
        conn
        |> with_pat(insert(:user))
        |> put_credential(credential.id, credential_body(%{}))

      assert_problem(conn, 409, :id_taken, [])
      assert Repo.reload!(credential).name == "Theirs"
    end

    test "is refused with 409 on their own credential while it is being deleted",
         %{conn: conn} do
      user = insert(:user)

      credential =
        scheduled_for_deletion(existing_credential(user, insert(:project)))

      conn =
        conn
        |> with_pat(user)
        |> put_credential(credential.id, credential_body(%{"name" => "Renamed"}))

      assert_problem(conn, 409, :scheduled_for_deletion, [])
      assert Repo.reload!(credential).name == credential.name
    end

    test "learns only that the id is taken, not that someone else's credential is being deleted",
         %{conn: conn} do
      credential =
        scheduled_for_deletion(
          existing_credential(insert(:user), insert(:project))
        )

      conn =
        conn
        |> with_pat(insert(:user))
        |> put_credential(credential.id, credential_body(%{}))

      assert_problem(conn, 409, :id_taken, [])
    end

    test "links only to projects where they may create a project credential",
         %{conn: conn} do
      user = insert(:user)
      viewing = insert(:project, project_users: [%{user: user, role: :viewer}])
      id = Ecto.UUID.generate()

      conn =
        conn
        |> with_pat(user)
        |> put_credential(
          id,
          credential_body(%{"project_credentials" => links([viewing.id])})
        )

      assert_problem(conn, 422, :invalid, [
        %{
          "pointer" => "#/project_credentials/0/project_id",
          "code" => "no_access",
          "detail" => "you may not link a credential to this project"
        }
      ])

      refute Repo.get(Credential, id)
    end

    test "keeps a link they can't see, and leaves it out of the response",
         %{conn: conn} do
      owner = insert(:user)
      theirs = insert(:project, project_users: [%{user: owner, role: :owner}])
      unseen = insert(:project)
      credential = existing_credential(owner, unseen)

      response =
        conn
        |> with_pat(owner)
        |> put_credential(
          credential.id,
          credential_body(%{"project_credentials" => links([theirs.id])})
        )
        |> json_response(200)

      assert linked_project_ids(response) == [theirs.id]
      refute inspect(response) =~ unseen.id

      assert Repo.get_by(Lightning.Projects.ProjectCredential,
               project_id: unseen.id,
               credential_id: credential.id
             )
    end
  end

  describe "GET" do
    test "a service account with the scope reads any credential, never its body",
         %{conn: conn} do
      {conn, _account} = with_service_account(conn, ["credentials:write"])
      owner = insert(:user)
      project = insert(:project)
      credential = existing_credential(owner, project)

      conn = get(conn, ~p"/api/credentials/#{credential.id}")

      assert %{
               "credential" => %{
                 "id" => id,
                 "user_id" => user_id,
                 "projects" => []
               },
               "errors" => %{}
             } = response = json_response(conn, 200)

      assert {id, user_id} == {credential.id, owner.id}
      assert linked_project_ids(response) == [project.id]
      refute conn.resp_body =~ "password"

      conn
      |> get(~p"/api/credentials/#{Ecto.UUID.generate()}")
      |> assert_problem(404, :not_found, [])
    end

    test "a service account also holding projects:write sees the projects by name",
         %{conn: conn} do
      {conn, _account} =
        with_service_account(conn, ["credentials:write", "projects:write"])

      project = insert(:project)
      credential = existing_credential(insert(:user), project)

      response =
        conn
        |> get(~p"/api/credentials/#{credential.id}")
        |> json_response(200)

      assert [%{"id" => project_id}] = response["credential"]["projects"]
      assert project_id == project.id
    end

    test "a person reads only their own, seeing links only to projects they stand in",
         %{conn: conn} do
      owner = insert(:user)
      theirs = insert(:project, project_users: [%{user: owner, role: :owner}])

      winding_down =
        insert(:project,
          project_users: [%{user: owner, role: :owner}],
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      credential = existing_credential(owner, theirs)

      for project <- [insert(:project), winding_down],
          do:
            insert(:project_credential, credential: credential, project: project)

      response =
        conn
        |> with_pat(owner)
        |> get(~p"/api/credentials/#{credential.id}")
        |> json_response(200)

      assert linked_project_ids(response) == [theirs.id]
      assert [%{"id" => theirs_id}] = response["credential"]["projects"]
      assert theirs_id == theirs.id

      conn
      |> with_pat(insert(:user))
      |> get(~p"/api/credentials/#{credential.id}")
      |> assert_problem(403, :forbidden, [])
    end
  end

  test "GET costs the same number of queries however many projects it links",
       %{conn: conn} do
    owner = insert(:user)

    [first | rest] =
      insert_list(3, :project, project_users: [%{user: owner, role: :owner}])

    credential = existing_credential(owner, first)
    conn = with_pat(conn, owner)

    show = fn ->
      conn |> get(~p"/api/credentials/#{credential.id}") |> json_response(200)
    end

    one_link = count_queries(show)

    for project <- rest,
        do: insert(:project_credential, credential: credential, project: project)

    assert count_queries(show) == one_link
  end

  describe "PUT, a credential body that is refused" do
    setup :isolated_adaptors

    setup %{conn: conn} do
      seed_credential_schema("postgresql")
      {conn, _account} = with_service_account(conn, ["credentials:write"])
      %{conn: conn, owner: insert(:user)}
    end

    defp typed_body(owner, body) do
      credential_body(%{
        "owner" => owner.email,
        "schema" => "postgresql",
        "credential_bodies" => [%{"name" => "main", "body" => body}]
      })
    end

    test "is refused at each key its schema refuses", %{conn: conn, owner: owner} do
      id = Ecto.UUID.generate()

      conn
      |> put_credential(
        id,
        typed_body(owner, %{"host" => "acme", "port" => 5432})
      )
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/credential_bodies/0/body/host",
          "code" => "type",
          "detail" => "expected to be a URI or an IPv4 address"
        },
        %{
          "pointer" => "#/credential_bodies/0/body/database",
          "code" => "required",
          "detail" => "can't be blank"
        }
      ])

      refute Repo.get(Credential, id)
    end

    test "is refused at each key on a credential it replaces", %{
      conn: conn,
      owner: owner
    } do
      credential = existing_credential(owner, insert(:project))

      conn
      |> put_credential(
        credential.id,
        typed_body(owner, %{
          "host" => "https://db.example",
          "port" => "many",
          "database" => "acme"
        })
      )
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/credential_bodies/0/body/port",
          "code" => "type",
          "detail" => "is invalid"
        },
        # The schema also finds the uncast port missing.
        %{
          "pointer" => "#/credential_bodies/0/body/port",
          "code" => "required",
          "detail" => "can't be blank"
        }
      ])

      assert main_body(credential.id) == %{"password" => "old"}
    end

    test "answers 503 not_ready while the adaptor catalogue can't answer", %{
      conn: conn,
      owner: owner
    } do
      Mimic.stub(Lightning.Adaptors, :resolve_name, fn name -> {:ok, name} end)

      Mimic.stub(Lightning.Adaptors, :schema, fn _name ->
        {:error, :not_ready}
      end)

      id = Ecto.UUID.generate()

      conn =
        put_credential(
          conn,
          id,
          typed_body(owner, %{"host" => "https://db.example"})
        )

      assert_problem(conn, 503, :not_ready, [])
      assert get_resp_header(conn, "retry-after") == ["5"]
      refute Repo.get(Credential, id)
    end
  end

  describe "for a repo connection" do
    test "PUT and GET are refused with 403 for holding no grant", %{conn: conn} do
      project = insert(:project)
      repo_connection = insert(:project_repo_connection, project: project)
      credential = insert(:credential, user: insert(:user))

      conn =
        put_req_header(
          conn,
          "authorization",
          "Bearer " <> repo_connection.access_token
        )

      for refused <- [
            put_credential(conn, Ecto.UUID.generate(), credential_body(%{})),
            get(conn, ~p"/api/credentials/#{credential.id}")
          ] do
        assert_problem(refused, 403, :insufficient_scope)

        assert get_resp_header(refused, "www-authenticate") == [
                 ~s(Bearer error="insufficient_scope", scope="credentials:write")
               ]
      end
    end
  end
end
