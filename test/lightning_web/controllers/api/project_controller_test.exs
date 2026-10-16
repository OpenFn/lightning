defmodule LightningWeb.API.ProjectControllerTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
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

  test "a repo connection is refused projects for want of projects:write, whether or not the project exists",
       %{conn: conn} do
    project = insert(:project)
    repo_connection = insert(:project_repo_connection, project: project)

    conn =
      put_req_header(
        conn,
        "authorization",
        "Bearer " <> repo_connection.access_token
      )

    [
      ~p"/api/projects",
      ~p"/api/projects/#{project.id}",
      ~p"/api/projects/#{Ecto.UUID.generate()}"
    ]
    |> Enum.map(&get(conn, &1))
    |> assert_refused_for_scope("projects:write")
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

    test "page links carry the page size applied, not the one asked for", %{
      conn: conn,
      user: user
    } do
      insert(:project, project_users: [%{user_id: user.id}])

      links =
        conn
        |> get(~p"/api/projects?page=1&page_size=500")
        |> json_response(200)
        |> Map.fetch!("links")

      assert links["first"] ==
               "#{LightningWeb.Endpoint.url()}/api/projects?page=1&page_size=100"

      assert links["last"] == links["first"]
      assert {links["next"], links["prev"]} == {nil, nil}
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

    test "answers 404 for a project that doesn't exist, or an id that isn't a UUID",
         %{conn: conn} do
      for id <- [Ecto.UUID.generate(), "not-a-uuid"] do
        conn
        |> get(~p"/api/projects/#{id}")
        |> assert_problem(404, :not_found, [])
      end
    end

    test "with token for other project", %{conn: conn} do
      other_project = insert(:project)
      conn = get(conn, ~p"/api/projects/#{other_project.id}")
      assert_problem(conn, 404, :not_found, [])
    end

    test "a non-member is refused with 404, not 409, on a project scheduled for deletion",
         %{conn: conn} do
      conn = get(conn, ~p"/api/projects/#{scheduled_project().id}")

      assert_problem(conn, 404, :not_found, [])
    end

    test "the owner gets 409 on a project scheduled for deletion",
         %{conn: conn, user: user} do
      project = scheduled_project([%{user: user, role: :owner}])

      conn = get(conn, ~p"/api/projects/#{project.id}")

      assert_problem(conn, 409, :scheduled_for_deletion, [])
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

      assert_problem(conn, 409, :scheduled_for_deletion, [])
    end
  end

  describe "show, for a repo connection" do
    test "is refused its own project for not holding projects:write", %{
      conn: conn
    } do
      project = insert(:project)
      repo_connection = insert(:project_repo_connection, project: project)

      conn =
        conn
        |> put_req_header(
          "authorization",
          "Bearer " <> repo_connection.access_token
        )
        |> get(~p"/api/projects/#{project.id}")

      assert_problem(conn, 403, :insufficient_scope)

      assert get_resp_header(conn, "www-authenticate") == [
               ~s(Bearer error="insufficient_scope", scope="projects:write")
             ]
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

    test "refuses a blank name on replace as it does on create", %{conn: conn} do
      project = insert(:project, name: "before")

      blank_name = [
        %{
          "pointer" => "#/name",
          "code" => "required",
          "detail" => "can't be blank"
        }
      ]

      conn
      |> put_project(project.id, %{"name" => ""})
      |> assert_problem(422, :invalid, blank_name)

      conn
      |> put_project(Ecto.UUID.generate(), %{
        "name" => "",
        "members" => four_members()
      })
      |> assert_problem(422, :invalid, blank_name)

      assert Lightning.Repo.reload!(project).name == "before"
    end

    test "refuses a body id that differs from the path", %{conn: conn} do
      conn =
        put_project(conn, Ecto.UUID.generate(), %{
          "id" => Ecto.UUID.generate(),
          "name" => "acme",
          "members" => four_members()
        })

      assert_problem(conn, 422, :invalid, [
        %{
          "pointer" => "#/id",
          "code" => "mismatch",
          "detail" => "does not match the id in the path"
        }
      ])
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

      assert_problem(conn, 422, :invalid, [
        %{
          "pointer" => "#/requires_mfa",
          "code" => "unknown_key",
          "detail" => "is not accepted"
        },
        %{
          "pointer" => "#/retention_policy",
          "code" => "unknown_key",
          "detail" => "is not accepted"
        }
      ])

      refute Lightning.Repo.get(Lightning.Projects.Project, id)
    end

    test "answers 404 for a path id that is not a UUID", %{conn: conn} do
      conn =
        put_project(conn, "not-a-uuid", %{
          "name" => "acme",
          "members" => four_members()
        })

      assert_problem(conn, 404, :not_found, [])
    end

    test "refuses members it cannot write, each at its place in members", %{
      conn: conn
    } do
      [owner, admin | _] = four_members()

      one_owner = fn detail ->
        %{"pointer" => "#/members", "code" => "one_owner", "detail" => detail}
      end

      refused = [
        unknown_email: {
          [owner, %{"email" => "nobody@example.com", "role" => "admin"}],
          [
            %{
              "pointer" => "#/members/1/email",
              "code" => "not_found",
              "detail" => "names nothing you can see"
            }
          ]
        },
        missing_email_and_unknown_role: {
          [owner, %{"role" => "admin"}, %{admin | "role" => "boss"}],
          [
            %{
              "pointer" => "#/members/1/email",
              "code" => "required",
              "detail" => "can't be blank"
            },
            %{
              "pointer" => "#/members/2/role",
              "code" => "not_allowed",
              "detail" => "is invalid"
            }
          ]
        },
        two_owners: {
          [owner, %{admin | "role" => "owner"}],
          [one_owner.("A project can have only one owner.")]
        },
        no_owner: {
          [admin],
          [
            one_owner.(
              "Every project must have exactly one owner. Please specify one below."
            )
          ]
        },
        no_members: {
          [],
          [
            %{
              "pointer" => "#/members",
              "code" => "required",
              "detail" => "can't be blank"
            },
            one_owner.(
              "Every project must have exactly one owner. Please specify one below."
            )
          ]
        },
        not_a_list: {
          %{"email" => owner["email"], "role" => "owner"},
          [
            %{
              "pointer" => "#/members",
              "code" => "type",
              "detail" => "is invalid"
            }
          ]
        }
      ]

      for {case_name, {members, entries}} <- refused do
        id = Ecto.UUID.generate()

        response =
          conn
          |> put_project(id, %{"name" => "acme", "members" => members})
          |> assert_problem(422, :invalid, entries)

        refute Jason.encode!(response) =~ "@",
               "#{case_name} echoes an email: #{inspect(response)}"

        refute Lightning.Repo.get(Lightning.Projects.Project, id)
      end
    end

    test "places a member's error by its position in the request, not the owner-last order members are written in",
         %{conn: conn} do
      [owner, admin, editor, _viewer] = four_members()

      conn
      |> put_project(Ecto.UUID.generate(), %{
        "name" => "acme",
        "members" => [
          owner,
          admin,
          %{"email" => "nobody@example.com", "role" => "editor"},
          %{admin | "email" => String.upcase(admin["email"])},
          editor,
          %{admin | "role" => "viewer"}
        ]
      })
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/members/2/email",
          "code" => "not_found",
          "detail" => "names nothing you can see"
        },
        %{
          "pointer" => "#/members/3/email",
          "code" => "duplicate",
          "detail" => "names the same user as #/members/1"
        },
        %{
          "pointer" => "#/members/5/email",
          "code" => "duplicate",
          "detail" => "names the same user as #/members/1"
        }
      ])
    end

    test "answers 402 with the members list when the project refuses a member for want of a seat",
         %{conn: conn} do
      # An extension refusing a member the way a seat limit does.
      Mox.expect(Lightning.Extensions.MockProjectHook, :handle_create_project, fn
        attrs ->
          %Lightning.Projects.Project{}
          |> Lightning.Projects.Project.project_with_users_changeset(attrs)
          |> Ecto.Changeset.add_error(:project_users, "has no seat left",
            code: :exceeds_limit
          )
          |> Ecto.Changeset.apply_action(:insert)
      end)

      conn
      |> put_project(Ecto.UUID.generate(), %{
        "name" => "acme",
        "members" => four_members()
      })
      |> assert_problem(402, :exceeds_limit, [
        %{
          "pointer" => "#/members",
          "code" => "exceeds_limit",
          "detail" => "has no seat left"
        }
      ])
    end

    test "reports every error in the body in one answer", %{conn: conn} do
      [owner | _] = four_members()
      id = Ecto.UUID.generate()

      conn
      |> put_project(id, %{
        "id" => Ecto.UUID.generate(),
        "name" => "Not Allowed",
        "colour" => "red",
        "notify" => "sometimes",
        "members" => [
          owner,
          %{"email" => "nobody@example.com", "role" => "admin"}
        ]
      })
      |> assert_problem(422, :invalid, [
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
        %{"pointer" => "#/notify", "code" => "type", "detail" => "is invalid"},
        %{
          "pointer" => "#/members/1/email",
          "code" => "not_found",
          "detail" => "names nothing you can see"
        },
        %{
          "pointer" => "#/name",
          "code" => "format",
          "detail" => "has invalid format"
        }
      ])

      refute Lightning.Repo.get(Lightning.Projects.Project, id)
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
        |> assert_problem(422, :invalid, [
          %{
            "pointer" => "#/notify",
            "code" => "required",
            "detail" => "can't be blank"
          }
        ])

      assert response["errors"]
      refute Lightning.Repo.get(Lightning.Projects.Project, id)
    end

    test "refuses a body that is not a JSON object", %{conn: conn} do
      conn = put_project(conn, Ecto.UUID.generate(), [%{"name" => "acme"}])

      assert_problem(conn, 400, :malformed, [])
    end

    test "refuses a name or description the project cannot hold", %{conn: conn} do
      conn_name =
        put_project(conn, Ecto.UUID.generate(), %{
          "name" => "Not Allowed",
          "members" => four_members()
        })

      assert_problem(conn_name, 422, :invalid, [
        %{
          "pointer" => "#/name",
          "code" => "format",
          "detail" => "has invalid format"
        }
      ])

      conn_description =
        put_project(conn, Ecto.UUID.generate(), %{
          "name" => "acme",
          "description" => String.duplicate("a", 241),
          "members" => four_members()
        })

      assert_problem(conn_description, 422, :invalid, [
        %{
          "pointer" => "#/description",
          "code" => "too_long",
          "detail" => "should be at most 240 character(s)"
        }
      ])
    end

    test "answers 409 for a project scheduled for deletion", %{conn: conn} do
      project = scheduled_project()

      conn = put_project(conn, project.id, %{"name" => "renamed"})

      assert_problem(conn, 409, :scheduled_for_deletion, [])
      assert Lightning.Repo.reload!(project).name == project.name
    end
  end

  describe "error answers on every projects route that has one" do
    setup %{conn: conn} do
      {conn, _account} = with_service_account(conn, ["projects:write"])

      %{
        conn: conn,
        planted:
          plant_sentinel(%{
            "id" => nil,
            "name" => nil,
            "description" => nil,
            "notify" => nil,
            "members" => [%{"email" => nil, "role" => nil}],
            "colour" => nil
          })
      }
    end

    test "never quote a value from the request", %{conn: conn, planted: planted} do
      conn
      |> get(~p"/api/projects/#{planted["name"]}")
      |> refute_sentinel()
      |> assert_problem(404, :not_found)

      conn
      |> put_project(planted["name"], planted)
      |> refute_sentinel()
      |> assert_problem(404, :not_found)

      conn
      |> put_project(Ecto.UUID.generate(), planted)
      |> refute_sentinel()
      |> assert_problem(422, :invalid)

      conn
      |> put_project(insert(:project).id, planted)
      |> refute_sentinel()
      |> assert_problem(422, :invalid)
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

        assert_problem(refused, 403, :insufficient_scope)

        assert get_resp_header(refused, "www-authenticate") == [
                 ~s(Bearer error="insufficient_scope", scope="projects:write")
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

      assert_problem(conn, 403, :forbidden, [])
      refute Lightning.Repo.get(Lightning.Projects.Project, id)
    end

    test "the owner or an admin replaces it; an editor, viewer or non-member is refused",
         %{conn: conn} do
      for {role, status} <- [
            owner: 200,
            admin: 200,
            editor: 403,
            viewer: 403,
            none: 404
          ] do
        user = insert(:user)

        project_users =
          if role == :none, do: [], else: [%{user: user, role: role}]

        project = insert(:project, name: "before", project_users: project_users)

        replaced =
          conn
          |> with_pat(user)
          |> put_project(project.id, %{"name" => "after"})

        case status do
          200 -> json_response(replaced, 200)
          403 -> assert_problem(replaced, 403, :forbidden, [])
          404 -> assert_problem(replaced, 404, :not_found, [])
        end

        expected = if status == 200, do: "after", else: "before"

        assert Lightning.Repo.reload!(project).name == expected,
               "#{role} got #{status}"
      end
    end

    test "a non-member is refused with 404, not 409, on a project scheduled for deletion",
         %{conn: conn} do
      project = scheduled_project()

      conn =
        conn
        |> with_pat(insert(:user))
        |> put_project(project.id, %{"name" => "renamed"})

      assert_problem(conn, 404, :not_found, [])
    end

    test "the owner gets 409 on a project scheduled for deletion, and nothing changes",
         %{conn: conn} do
      user = insert(:user)
      project = scheduled_project([%{user: user, role: :owner}])

      conn =
        conn
        |> with_pat(user)
        |> put_project(project.id, %{"name" => "renamed"})

      assert_problem(conn, 409, :scheduled_for_deletion, [])
      assert Lightning.Repo.reload!(project).name == project.name
    end

    test "a non-member with a bad body is refused before the body is read",
         %{conn: conn} do
      conn =
        conn
        |> with_pat(insert(:user))
        |> put_project(insert(:project).id, %{"nonsense" => 1})

      assert_problem(conn, 404, :not_found, [])
    end
  end
end
