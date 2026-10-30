defmodule LightningWeb.API.Credentials.RefusalsTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiCredentialsHelpers
  import Lightning.ServiceAccountHelpers
  import Lightning.AdaptorTestHelpers
  import Lightning.RaceHelpers
  import Ecto.Query

  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Repo

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "a body it cannot parse" do
    setup [:assign_bearer_for_api]

    test "answers 400 malformed for a body that is not a JSON object", %{
      conn: conn,
      user: user
    } do
      for body <- ["Listed", 7] do
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/credentials", Jason.encode!(body))
        |> assert_problem(400, :malformed, [])
      end

      assert Lightning.Credentials.list_credentials(user) == []
    end
  end

  describe "a body its keys refuse" do
    setup [:assign_bearer_for_api]

    test "refuses a blank name, and a body without a schema, at the key", %{
      conn: conn,
      user: user
    } do
      required = fn pointer ->
        %{
          "pointer" => pointer,
          "code" => "required",
          "detail" => "can't be blank"
        }
      end

      for {attrs, entries} <- [
            {credential_body(%{"name" => ""}), [required.("#/name")]},
            {%{"name" => ""}, [required.("#/name"), required.("#/schema")]}
          ] do
        conn
        |> post(~p"/api/credentials", attrs)
        |> assert_problem(422, :invalid, entries)
      end

      assert Credentials.list_credentials(user) == []
    end
  end

  describe "a link it cannot make" do
    test "refuses a link it can't make, at the link, on POST and PUT", %{
      conn: conn
    } do
      user = insert(:user)
      unseen = insert(:project)

      member =
        insert(:project, project_users: [%{user: user, role: :editor}])

      not_found = fn position ->
        %{
          "pointer" => "#/project_credentials/#{position}/project_id",
          "code" => "not_found",
          "detail" => "names nothing you can see"
        }
      end

      not_valid = fn pointer, code, detail ->
        %{"pointer" => pointer, "code" => code, "detail" => detail}
      end

      refused = [
        {[%{"project_id" => unseen.id}], [not_found.(0)]},
        {[%{"project_id" => Ecto.UUID.generate()}], [not_found.(0)]},
        {[%{"project_id" => "not-a-uuid"}], [not_found.(0)]},
        {[%{"project_id" => 42}],
         [
           not_valid.(
             "#/project_credentials/0/project_id",
             "type",
             "is invalid"
           )
         ]},
        {[%{}],
         [
           not_valid.(
             "#/project_credentials/0/project_id",
             "required",
             "can't be blank"
           )
         ]},
        {["acme"],
         [not_valid.("#/project_credentials/0", "type", "is invalid")]},
        {%{"project_id" => Ecto.UUID.generate()},
         [not_valid.("#/project_credentials", "type", "is invalid")]},
        {[
           %{"project_id" => unseen.id},
           %{"project_id" => member.id},
           %{"project_id" => unseen.id}
         ], [not_found.(0), not_found.(2)]}
      ]

      conn = with_pat(conn, user)

      for {link_list, entries} <- refused do
        body = credential_body(%{"project_credentials" => link_list})

        conn
        |> post(~p"/api/credentials", body)
        |> assert_problem(422, :invalid, entries)

        conn
        |> put_credential(Ecto.UUID.generate(), body)
        |> assert_problem(422, :invalid, entries)
      end

      assert Credentials.list_credentials(user) == []
    end

    test "answers no_access in the words for whoever is asking", %{conn: conn} do
      person = insert(:user)
      viewing = insert(:project, project_users: [%{user: person, role: :viewer}])
      elsewhere = insert(:project)

      {account_conn, _account} =
        with_service_account(conn, ["credentials:write"])

      requests = [
        {fn ->
           conn
           |> with_pat(person)
           |> post(
             ~p"/api/credentials",
             credential_body(%{"project_credentials" => links([viewing.id])})
           )
         end, "you may not link a credential to this project"},
        {fn ->
           conn
           |> with_pat(person)
           |> put_credential(
             Ecto.UUID.generate(),
             credential_body(%{"project_credentials" => links([viewing.id])})
           )
         end, "you may not link a credential to this project"},
        {fn ->
           put_credential(
             account_conn,
             Ecto.UUID.generate(),
             credential_body(%{
               "owner" => insert(:user).email,
               "project_credentials" => links([elsewhere.id])
             })
           )
         end, "the credential's owner is not a member of this project"}
      ]

      for {request, detail} <- requests do
        assert_problem(request.(), 422, :invalid, [
          %{
            "pointer" => "#/project_credentials/0/project_id",
            "code" => "no_access",
            "detail" => detail
          }
        ])
      end

      assert Repo.aggregate(Credential, :count) == 0
    end
  end

  describe "a name already held" do
    test "answers 422 invalid with a taken entry for a name the caller already holds, on POST and PUT",
         %{conn: conn} do
      user = insert(:user)
      held = insert(:credential, user: user, name: "Taken")
      renamed = insert(:credential, user: user, name: "Mine")
      new_id = Ecto.UUID.generate()
      conn = with_pat(conn, user)

      taken = [
        %{
          "pointer" => "#/name",
          "code" => "taken",
          "detail" => "you have another credential with the same name"
        }
      ]

      conn
      |> post(~p"/api/credentials", credential_body(%{"name" => "Taken"}))
      |> assert_problem(422, :invalid, taken)

      conn
      |> put_credential(new_id, credential_body(%{"name" => "Taken"}))
      |> assert_problem(422, :invalid, taken)

      refute Repo.get(Credential, new_id)

      conn
      |> put_credential(renamed.id, credential_body(%{"name" => held.name}))
      |> assert_problem(422, :invalid, taken)

      assert Repo.reload!(renamed).name == "Mine"
    end
  end

  describe "PUT, for a service account with credentials:write" do
    setup %{conn: conn} do
      {conn, account} = with_service_account(conn, ["credentials:write"])
      %{conn: conn, account: account}
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

    test "a credential another request deletes mid-replace answers 409 concurrent_edit",
         %{conn: conn} do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))

      after_first_query("credentials", credential.id, fn id ->
        for child <- ~w(credential_bodies project_credentials) do
          Repo.query!("DELETE FROM #{child} WHERE credential_id = $1", [id])
        end

        Repo.query!("DELETE FROM credentials WHERE id = $1", [id])
      end)

      conn
      |> put_credential(
        credential.id,
        credential_body(%{"name" => "Renamed", "owner" => owner.email})
      )
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(credential)
    end

    test "answers 422 not_allowed at the owner, writing nothing, when the body names another owner",
         %{
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

      assert_problem(conn, 422, :invalid, [
        %{
          "pointer" => "#/owner",
          "code" => "not_allowed",
          "detail" => "can't change when replacing a credential"
        }
      ])

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
  end

  describe "PUT, for a person's token" do
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
  end

  describe "a body its schema refuses, on POST and PUT" do
    setup [:assign_bearer_for_api]

    defp oauth_token(overrides) do
      Map.merge(
        %{
          "access_token" => "access",
          "refresh_token" => "refresh",
          "token_type" => "Bearer",
          "scope" => "read write",
          "expires_in" => 3600
        },
        overrides
      )
    end

    test "refuses an OAuth token at the key it refuses, on POST and PUT", %{
      conn: conn,
      user: user
    } do
      conn
      |> post(~p"/api/credentials", %{
        "name" => "OAuth",
        "schema" => "oauth",
        "credential_bodies" => [
          %{"name" => "main", "body" => oauth_token(%{})},
          %{
            "name" => "staging",
            "body" => oauth_token(%{"token_type" => "Basic"})
          }
        ]
      })
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/credential_bodies/1/body/token_type",
          "code" => "not_allowed",
          "detail" => "Unsupported token type. Expected 'Bearer'"
        }
      ])

      for {body, key, code, detail} <- [
            {oauth_token(%{"token_type" => "Basic"}), "token_type",
             "not_allowed", "Unsupported token type. Expected 'Bearer'"},
            {Map.delete(oauth_token(%{}), "access_token"), "access_token",
             "required", "Missing required OAuth field: access_token"}
          ] do
        attrs = %{
          "name" => "OAuth",
          "schema" => "oauth",
          "credential_bodies" => [%{"name" => "main", "body" => body}]
        }

        entries = [
          %{
            "pointer" => "#/credential_bodies/0/body/#{key}",
            "code" => code,
            "detail" => detail
          }
        ]

        conn
        |> post(~p"/api/credentials", attrs)
        |> assert_problem(422, :invalid, entries)

        conn
        |> put_credential(Ecto.UUID.generate(), attrs)
        |> assert_problem(422, :invalid, entries)
      end

      assert Credentials.list_credentials(user) == []
    end
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
        # The failed cast leaves no port, so the required check reports it too.
        %{
          "pointer" => "#/credential_bodies/0/body/port",
          "code" => "required",
          "detail" => "can't be blank"
        }
      ])

      assert main_body(credential.id) == %{"password" => "old"}
    end

    test "answers 503 not_ready while the adaptor catalogue can't answer, whatever else the body gets wrong",
         %{conn: conn, owner: owner} do
      stub_unloaded_catalogue()
      id = Ecto.UUID.generate()

      conn =
        put_credential(
          conn,
          id,
          owner
          |> typed_body(%{"host" => "https://db.example"})
          |> Map.merge(%{"name" => nil, "colour" => "blue"})
        )

      assert_problem(conn, 503, :not_ready, [])
      assert get_resp_header(conn, "retry-after") == ["5"]
      refute Repo.get(Credential, id)
    end

    test "answers 503 not_ready to a refused replace that keeps the credential's schema, while the catalogue can't answer",
         %{conn: conn, owner: owner} do
      stub_unloaded_catalogue()

      credential =
        insert(:credential, schema: "postgresql", user: owner)
        |> with_body(%{name: "main", body: %{"host" => "https://db.example"}})

      body =
        owner
        |> typed_body(%{"host" => "https://db.example"})
        |> Map.drop(["schema"])
        |> Map.put("colour", "blue")

      conn
      |> put_credential(credential.id, body)
      |> assert_problem(503, :not_ready, [])
    end
  end

  describe "POST, while the adaptor catalogue can't answer" do
    setup [:assign_bearer_for_api]

    test "answers 503 not_ready, whatever else the body gets wrong", %{
      conn: conn,
      user: user
    } do
      stub_unloaded_catalogue()

      conn
      |> post(
        ~p"/api/credentials",
        credential_body(%{
          "name" => nil,
          "schema" => "postgresql",
          "project_credentials" => [%{"project_id" => Ecto.UUID.generate()}]
        })
      )
      |> assert_problem(503, :not_ready, [])

      assert Credentials.list_credentials(user) == []
    end
  end

  describe "DELETE, refused" do
    setup [:assign_bearer_for_api]

    test "answers 409 in_use for a credential runs have used", %{
      conn: conn,
      user: user
    } do
      credential = insert(:credential, user: user, schema: "raw")
      insert(:step, credential: credential)

      conn
      |> delete(~p"/api/credentials/#{credential.id}")
      |> assert_problem(409, :in_use, [])

      assert Lightning.Credentials.get_credential(credential.id)
    end
  end

  describe "error answers on every credentials route" do
    setup [:assign_bearer_for_api]

    test "never quotes a value planted in the credential's own keys, on POST and PUT",
         %{conn: conn, user: user} do
      # A loaded catalogue with no adaptor of the planted name, so the planted
      # schema gets past the wait for the catalogue to the body's checks.
      Mimic.stub(Lightning.Adaptors, :resolve_name, fn name -> {:ok, name} end)

      Mimic.stub(Lightning.Adaptors, :schema, fn _name ->
        {:error, :not_found}
      end)

      planted =
        plant_sentinel(%{
          "id" => nil,
          "name" => nil,
          "schema" => nil,
          "owner" => nil,
          "colour" => nil,
          "credential_bodies" => [%{"name" => nil, "body" => %{"key" => nil}}],
          "project_credentials" => [%{"project_id" => nil, "extra" => nil}]
        })

      conn
      |> post(~p"/api/credentials", planted)
      |> refute_sentinel()
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/project_credentials/0/project_id",
          "code" => "not_found",
          "detail" => "names nothing you can see"
        }
      ])

      conn
      |> post(~p"/api/credentials", %{
        "name" => "OAuth",
        "schema" => "oauth",
        "credential_bodies" =>
          plant_sentinel([
            %{
              "name" => "main",
              "body" => %{
                "access_token" => [nil],
                "refresh_token" => nil,
                "token_type" => nil,
                "scope" => nil,
                "expires_in" => nil
              }
            }
          ])
      })
      |> refute_sentinel()
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/credential_bodies/0/body/access_token",
          "code" => "type",
          "detail" => "access_token must be a non-empty string"
        }
      ])

      {account_conn, _account} =
        with_service_account(conn, ["credentials:write"])

      base = [
        %{
          "pointer" => "#/colour",
          "code" => "unknown_key",
          "detail" => "is not accepted"
        },
        %{
          "pointer" => "#/id",
          "code" => "mismatch",
          "detail" => "does not match the id in the path"
        },
        %{
          "pointer" => "#/credential_bodies",
          "code" => "one_body",
          "detail" => "must be one body named main, holding an object"
        }
      ]

      rest = [
        %{
          "pointer" => "#/project_credentials/0/project_id",
          "code" => "not_found",
          "detail" => "names nothing you can see"
        },
        %{
          "pointer" => "#/project_credentials/0/extra",
          "code" => "unknown_key",
          "detail" => "is not accepted"
        }
      ]

      for {owner, entries} <- [
            {planted["owner"],
             base ++
               [
                 %{
                   "pointer" => "#/owner",
                   "code" => "not_found",
                   "detail" => "names nothing you can see"
                 }
               ] ++ rest},
            {user.email, base ++ rest}
          ] do
        account_conn
        |> put_credential(Ecto.UUID.generate(), Map.put(planted, "owner", owner))
        |> refute_sentinel()
        |> assert_problem(422, :invalid, entries)
      end
    end
  end

  defp stub_unloaded_catalogue do
    Mimic.stub(Lightning.Adaptors, :resolve_name, fn _name ->
      {:error, :not_ready}
    end)
  end
end
