defmodule LightningWeb.API.Projects.RefusingABodyTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiProjectsHelpers
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "refusing a body, with a service account that has projects:write" do
    setup %{conn: conn} do
      {conn, account} = with_service_account(conn, ["projects:write"])
      %{conn: conn, account: account}
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

    test "reports every error in the body in one answer, an unknown key and a mismatched id among them",
         %{conn: conn} do
      [owner | _] = four_members()
      id = Ecto.UUID.generate()

      conn
      |> put_project(id, %{
        "id" => Ecto.UUID.generate(),
        "name" => "Not Allowed",
        "requires_mfa" => true,
        "notify" => "sometimes",
        "members" => [
          owner,
          %{"email" => "nobody@example.com", "role" => "admin"}
        ]
      })
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/requires_mfa",
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
  end

  describe "answers that quote nothing from the request" do
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

    test "never quote a value from the request, a member's email and role among them",
         %{conn: conn, planted: planted} do
      conn
      |> get(~p"/api/projects/#{planted["name"]}")
      |> refute_sentinel()
      |> assert_problem(400, :invalid_parameter, [
        not_a_uuid_entry(%{"path" => "id"})
      ])

      conn
      |> put_project(planted["name"], planted)
      |> refute_sentinel()
      |> assert_problem(400, :invalid_parameter, [
        not_a_uuid_entry(%{"path" => "id"})
      ])

      conn
      |> put_project(Ecto.UUID.generate(), planted)
      |> refute_sentinel()
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
          "pointer" => "#/members/0/role",
          "code" => "not_allowed",
          "detail" => "is invalid"
        }
      ])

      conn
      |> put_project(insert(:project).id, planted)
      |> refute_sentinel()
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
        %{"pointer" => "#/notify", "code" => "type", "detail" => "is invalid"}
      ])
    end
  end
end
