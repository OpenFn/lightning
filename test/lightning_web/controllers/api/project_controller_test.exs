defmodule LightningWeb.API.ProjectControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Ecto.Query
  import Lightning.ServiceAccountHelpers

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "without a token" do
    test "gets a 401", %{conn: conn} do
      conn = get(conn, ~p"/api/projects")
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "with invalid token" do
    test "gets a 401", %{conn: conn} do
      token = "Oooops"
      conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      conn = get(conn, ~p"/api/projects")
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  # Proves the plug is wired into the /api scope, rather than only that the
  # plug function itself refuses — see user_auth_test.exs for the unit tests.
  describe "with an account past its confirmation deadline" do
    test "gets a 401, and the same token works again once confirmed", %{
      conn: conn
    } do
      Mox.stub(Lightning.MockConfig, :check_flag?, fn
        :require_email_verification -> true
        flag -> Lightning.Config.API.check_flag?(flag)
      end)

      user = insert(:user)
      insert(:project, project_users: [%{user: user}])

      token = Lightning.Accounts.generate_api_token(user)

      user =
        user
        |> Ecto.Changeset.change(
          confirmed_at: nil,
          inserted_at:
            DateTime.utc_now()
            |> DateTime.add(-50, :hour)
            |> DateTime.truncate(:second)
        )
        |> Lightning.Repo.update!()

      refused = conn |> assign_bearer(token) |> get(~p"/api/projects")

      assert json_response(refused, 401) == %{"error" => "Unauthorized"}

      user
      |> Ecto.Changeset.change(
        confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )
      |> Lightning.Repo.update!()

      allowed = conn |> assign_bearer(token) |> get(~p"/api/projects")

      assert [%{"type" => "projects"}] = json_response(allowed, 200)["data"]
    end
  end

  describe "index" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "lists all projects i belong to", %{conn: conn, project: project} do
      conn = get(conn, ~p"/api/projects")
      response = json_response(conn, 200)

      assert response["data"] == [
               %{
                 "attributes" => %{
                   "name" => project.name,
                   "description" => nil
                 },
                 "id" => project.id,
                 "links" => %{
                   "self" =>
                     "#{LightningWeb.Endpoint.url()}/api/projects/#{project.id}"
                 },
                 "relationships" => %{},
                 "type" => "projects"
               }
             ]
    end

    test "Other user don't have access to user project", %{
      conn: conn,
      project: project
    } do
      other_user = insert(:user)

      token =
        other_user
        |> Lightning.Accounts.generate_api_token()

      conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")

      insert(:project, project_users: [%{user_id: other_user.id}])

      conn = get(conn, ~p"/api/projects")
      response = json_response(conn, 200)

      refute response["data"] == [
               %{
                 "attributes" => %{"name" => "a-test-project"},
                 "id" => project.id,
                 "links" => %{
                   "self" =>
                     "#{LightningWeb.Endpoint.url()}/api/projects/#{project.id}"
                 },
                 "relationships" => %{},
                 "type" => "projects"
               }
             ]
    end
  end

  describe "show" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "returns 404 for non-existent project", %{conn: conn} do
      conn = get(conn, ~p"/api/projects/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end

    test "with token for other project", %{conn: conn} do
      other_project = insert(:project)
      conn = get(conn, ~p"/api/projects/#{other_project.id}")
      assert json_response(conn, 403) == %{"error" => "Forbidden"}
    end

    test "is refused with 403, not 409, on a project scheduled for deletion",
         %{conn: conn, user: user} do
      project = scheduled_project([%{user: user, role: :owner}])

      conn = get(conn, ~p"/api/projects/#{project.id}")

      assert json_response(conn, 403) == %{"error" => "Forbidden"}
    end

    test "shows the project with its members", %{
      conn: conn,
      project: project,
      user: user
    } do
      conn = get(conn, Routes.api_project_path(conn, :show, project))
      response = json_response(conn, 200)

      assert response["data"] == %{
               "attributes" => %{
                 "name" => project.name,
                 "description" => nil,
                 "members" => [%{"email" => user.email, "role" => "editor"}]
               },
               "id" => project.id,
               "links" => %{
                 "self" =>
                   "#{LightningWeb.Endpoint.url()}/api/projects/#{project.id}"
               },
               "relationships" => %{},
               "type" => "projects"
             }
    end
  end

  describe "show, for a service account with projects:write" do
    setup %{conn: conn} do
      {conn, _account} = with_service_account(conn, ["projects:write"])
      %{conn: conn}
    end

    test "shows a project it is not a member of, with its members", %{
      conn: conn
    } do
      owner = insert(:user)
      project = insert(:project, project_users: [%{user: owner, role: :owner}])

      conn = get(conn, ~p"/api/projects/#{project.id}")

      assert %{"id" => id, "attributes" => attributes} =
               json_response(conn, 200)["data"]

      assert id == project.id

      assert attributes == %{
               "name" => project.name,
               "description" => project.description,
               "members" => [%{"email" => owner.email, "role" => "owner"}]
             }
    end

    test "answers 409 for a project scheduled for deletion", %{conn: conn} do
      conn = get(conn, ~p"/api/projects/#{scheduled_project().id}")

      assert json_response(conn, 409) == %{"error" => "scheduled_for_deletion"}
    end
  end

  describe "show, for a repo connection" do
    test "is refused its own project with 403", %{conn: conn} do
      project = insert(:project)
      repo_connection = insert(:project_repo_connection, project: project)

      conn =
        conn
        |> put_req_header(
          "authorization",
          "Bearer " <> repo_connection.access_token
        )
        |> get(~p"/api/projects/#{project.id}")

      assert json_response(conn, 403) == %{"error" => "Forbidden"}
    end
  end

  defp put_project(conn, id, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put(~p"/api/projects/#{id}", Jason.encode!(body))
  end

  defp with_pat(conn, user) do
    assign_bearer(conn, Lightning.Accounts.generate_api_token(user))
  end

  defp members_of(project_id) do
    from(pu in Lightning.Projects.ProjectUser,
      join: u in assoc(pu, :user),
      where: pu.project_id == ^project_id,
      select: {u.email, pu.role}
    )
    |> Lightning.Repo.all()
    |> Enum.sort()
  end

  defp sorted_members(response) do
    response["data"]["attributes"]["members"]
    |> Enum.sort_by(& &1["email"])
  end

  defp four_members do
    for role <- ~w(owner admin editor viewer) do
      %{"email" => insert(:user).email, "role" => role}
    end
  end

  defp scheduled_project(project_users \\ []) do
    insert(:project,
      scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second),
      project_users: project_users
    )
  end

  describe "PUT, for a service account with projects:write" do
    setup %{conn: conn} do
      {conn, account} = with_service_account(conn, ["projects:write"])
      %{conn: conn, account: account}
    end

    test "creates the project with its members, and is not one of them", %{
      conn: conn,
      account: account
    } do
      id = Ecto.UUID.generate()
      members = four_members()

      conn =
        put_project(conn, id, %{
          "name" => "acme",
          "description" => "The acme project",
          "members" => members,
          "notify" => false
        })

      response = json_response(conn, 201)

      assert %{
               "id" => ^id,
               "type" => "projects",
               "attributes" => %{
                 "name" => "acme",
                 "description" => "The acme project"
               }
             } = response["data"]

      assert sorted_members(response) == Enum.sort_by(members, & &1["email"])

      assert members_of(id) ==
               members
               |> Enum.map(&{&1["email"], String.to_existing_atom(&1["role"])})
               |> Enum.sort()

      actors =
        from(a in Lightning.Auditing.Audit,
          where: a.item_id == ^id,
          select: {a.event, a.actor_id, a.actor_type}
        )
        |> Lightning.Repo.all()

      assert Enum.count(actors, &match?({"collaborator_added", _, _}, &1)) == 4
      assert {"created", account.uuid, :service_account} in actors

      assert Enum.all?(actors, fn {_, actor_id, actor_type} ->
               actor_id == account.uuid and actor_type == :service_account
             end)
    end

    test "emails the members it adds unless told not to", %{conn: conn} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        quiet_id = Ecto.UUID.generate()

        put_project(conn, quiet_id, %{
          "name" => "quiet",
          "members" => four_members(),
          "notify" => false
        })
        |> json_response(201)

        assert all_enqueued(worker: Lightning.Accounts.UserNotifier) == []

        put_project(conn, Ecto.UUID.generate(), %{
          "name" => "loud",
          "members" => four_members()
        })
        |> json_response(201)

        assert length(all_enqueued(worker: Lightning.Accounts.UserNotifier)) ==
                 4
      end)
    end

    test "matches a member's email without regard to case", %{conn: conn} do
      owner = insert(:user, email: "mixed.case@example.com")
      id = Ecto.UUID.generate()

      conn =
        put_project(conn, id, %{
          "name" => "acme",
          "members" => [
            %{"email" => "Mixed.CASE@example.com", "role" => "owner"}
          ]
        })

      assert json_response(conn, 201)
      assert members_of(id) == [{owner.email, :owner}]
    end

    test "replaces the name and description and keeps the members", %{
      conn: conn
    } do
      owner = insert(:user)

      project =
        insert(:project,
          name: "before",
          description: "old",
          project_users: [%{user: owner, role: :owner}]
        )

      conn =
        put_project(conn, project.id, %{
          "name" => "after",
          "description" => "new",
          "members" => [%{"email" => insert(:user).email, "role" => "owner"}]
        })

      response = json_response(conn, 200)

      assert response["data"]["attributes"] == %{
               "name" => "after",
               "description" => "new",
               "members" => [%{"email" => owner.email, "role" => "owner"}]
             }

      assert %{name: "after", description: "new"} =
               Lightning.Repo.reload!(project)

      assert members_of(project.id) == [{owner.email, :owner}]
    end

    test "refuses a body id that differs from the path", %{conn: conn} do
      conn =
        put_project(conn, Ecto.UUID.generate(), %{
          "id" => Ecto.UUID.generate(),
          "name" => "acme",
          "members" => four_members()
        })

      assert %{"id" => [_]} = json_response(conn, 422)["errors"]
    end

    test "refuses a key the body does not take, under that key", %{conn: conn} do
      id = Ecto.UUID.generate()

      conn =
        put_project(conn, id, %{
          "name" => "acme",
          "members" => four_members(),
          "requires_mfa" => true,
          "retention_policy" => "erase_all"
        })

      assert json_response(conn, 422) == %{
               "errors" => %{
                 "requires_mfa" => ["is not accepted"],
                 "retention_policy" => ["is not accepted"]
               }
             }

      refute Lightning.Repo.get(Lightning.Projects.Project, id)
    end

    test "refuses a path id that is not a UUID", %{conn: conn} do
      conn =
        put_project(conn, "not-a-uuid", %{
          "name" => "acme",
          "members" => four_members()
        })

      assert %{"id" => [_]} = json_response(conn, 422)["errors"]
    end

    test "refuses members it cannot write, under members", %{conn: conn} do
      [owner, admin | _] = four_members()

      refused = [
        unknown_email: [
          owner,
          %{"email" => "nobody@example.com", "role" => "admin"}
        ],
        two_owners: [owner, %{admin | "role" => "owner"}],
        no_owner: [admin],
        no_members: [],
        not_a_list: %{"email" => owner["email"], "role" => "owner"}
      ]

      for {case_name, members} <- refused do
        id = Ecto.UUID.generate()

        response =
          conn
          |> put_project(id, %{"name" => "acme", "members" => members})
          |> json_response(422)

        assert %{"members" => [_ | _] = messages} = response["errors"],
               "#{case_name}: #{inspect(response)}"

        assert map_size(response["errors"]) == 1 and
                 Enum.all?(messages, &is_binary/1),
               "#{case_name}: #{inspect(response)}"

        refute Enum.any?(messages, &String.contains?(&1, "@")),
               "#{case_name} echoes an email: #{inspect(response)}"

        refute Lightning.Repo.get(Lightning.Projects.Project, id)
      end
    end

    test "lists a member the project refuses as a plain message under members",
         %{conn: conn} do
      # An extension refusing one member, the way a seat limit would.
      Mox.expect(Lightning.Extensions.MockProjectHook, :handle_create_project, fn
        attrs ->
          changeset =
            Lightning.Projects.Project.project_with_users_changeset(
              %Lightning.Projects.Project{},
              attrs
            )

          [first | rest] = Ecto.Changeset.get_change(changeset, :project_users)

          changeset
          |> Ecto.Changeset.put_change(:project_users, [
            first,
            rest
            |> hd()
            |> Ecto.Changeset.add_error(:user_id, "has no seat left")
            | tl(rest)
          ])
          |> Ecto.Changeset.apply_action(:insert)
      end)

      response =
        conn
        |> put_project(Ecto.UUID.generate(), %{
          "name" => "acme",
          "members" => four_members()
        })
        |> json_response(422)

      assert response["errors"] == %{"members" => ["has no seat left"]}
    end

    test "refuses a notify of null, under notify", %{conn: conn} do
      id = Ecto.UUID.generate()

      response =
        conn
        |> put_project(id, %{
          "name" => "acme",
          "members" => four_members(),
          "notify" => nil
        })
        |> json_response(422)

      assert %{"notify" => [_]} = response["errors"]
      refute Lightning.Repo.get(Lightning.Projects.Project, id)
    end

    test "refuses a body that is not a JSON object", %{conn: conn} do
      conn = put_project(conn, Ecto.UUID.generate(), [%{"name" => "acme"}])

      assert %{"errors" => %{"body" => [_]}} = json_response(conn, 422)
    end

    test "refuses a name or description the project cannot hold", %{conn: conn} do
      conn_name =
        put_project(conn, Ecto.UUID.generate(), %{
          "name" => "Not Allowed",
          "members" => four_members()
        })

      assert Map.keys(json_response(conn_name, 422)["errors"]) == ["name"]

      conn_description =
        put_project(conn, Ecto.UUID.generate(), %{
          "name" => "acme",
          "description" => String.duplicate("a", 241),
          "members" => four_members()
        })

      assert Map.keys(json_response(conn_description, 422)["errors"]) == [
               "description"
             ]
    end

    test "answers 409 for a project scheduled for deletion", %{conn: conn} do
      project = scheduled_project()

      conn = put_project(conn, project.id, %{"name" => "renamed"})

      assert json_response(conn, 409) == %{"error" => "scheduled_for_deletion"}
      assert Lightning.Repo.reload!(project).name == project.name
    end
  end

  describe "PUT, for a service account without projects:write" do
    test "is refused for insufficient scope, creating or replacing", %{
      conn: conn
    } do
      {conn, _account} = with_service_account(conn, ["users:write"])

      for id <- [Ecto.UUID.generate(), insert(:project).id] do
        refused =
          put_project(conn, id, %{"name" => "acme", "members" => four_members()})

        assert json_response(refused, 403) == %{"error" => "insufficient_scope"}

        assert get_resp_header(refused, "www-authenticate") == [
                 ~s(Bearer error="insufficient_scope")
               ]
      end
    end
  end

  describe "PUT, for a person's token" do
    test "a superuser creates a project", %{conn: conn} do
      conn = with_pat(conn, insert(:user, role: :superuser))
      id = Ecto.UUID.generate()

      conn =
        put_project(conn, id, %{"name" => "acme", "members" => four_members()})

      assert %{"id" => ^id} = json_response(conn, 201)["data"]
    end

    test "anyone else is refused creating one", %{conn: conn} do
      conn = with_pat(conn, insert(:user))
      id = Ecto.UUID.generate()

      conn =
        put_project(conn, id, %{"name" => "acme", "members" => four_members()})

      assert json_response(conn, 403) == %{"error" => "Forbidden"}
      refute Lightning.Repo.get(Lightning.Projects.Project, id)
    end

    test "the owner or an admin replaces it; an editor, viewer or non-member is refused",
         %{conn: conn} do
      for {role, status} <- [
            owner: 200,
            admin: 200,
            editor: 403,
            viewer: 403,
            none: 403
          ] do
        user = insert(:user)

        project_users =
          if role == :none, do: [], else: [%{user: user, role: role}]

        project = insert(:project, name: "before", project_users: project_users)

        conn
        |> with_pat(user)
        |> put_project(project.id, %{"name" => "after"})
        |> json_response(status)

        expected = if status == 200, do: "after", else: "before"

        assert Lightning.Repo.reload!(project).name == expected,
               "#{role} got #{status}"
      end
    end

    test "is refused with 403, not 409, on a project scheduled for deletion",
         %{conn: conn} do
      user = insert(:user)
      project = scheduled_project([%{user: user, role: :owner}])

      conn =
        conn
        |> with_pat(user)
        |> put_project(project.id, %{"name" => "renamed"})

      assert json_response(conn, 403) == %{"error" => "Forbidden"}
    end
  end
end
