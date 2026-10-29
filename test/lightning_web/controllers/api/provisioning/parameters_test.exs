defmodule LightningWeb.API.ProvisioningParametersTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProvisioningHelpers
  import LightningWeb.API.ProblemHelpers
  import Lightning.Factories

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "parameters and identifiers" do
    setup [:assign_bearer_for_api]

    setup %{user: user} do
      %{
        project:
          insert(:project, project_users: [%{user_id: user.id, role: :owner}])
      }
    end

    test "a project id in the body that isn't a UUID is refused to a person who isn't a superuser, and invalid at the id to a superuser",
         %{conn: conn} do
      %{body: body} = valid_payload("not-a-uuid")
      superuser = insert(:user, role: :superuser)

      superuser_conn =
        put_req_header(
          conn,
          "authorization",
          "Bearer " <> Lightning.Accounts.generate_api_token(superuser)
        )

      for {conn, status, code, entries} <- [
            {conn, 403, :forbidden, []},
            {superuser_conn, 422, :invalid,
             [
               not_a_uuid_entry(%{"pointer" => "#/id"})
             ]}
          ] do
        conn
        |> post(~p"/api/provision", body)
        |> assert_problem(status, code, entries)
      end
    end

    @tag login_as: "superuser"
    test "a project id in the body that isn't a UUID answers 422 type at the id to a caller who may create projects",
         %{conn: conn} do
      projects = Lightning.Repo.aggregate(Lightning.Projects.Project, :count)

      # A 16-byte string would cast to a UUID it doesn't spell.
      for id <- ["not-a-uuid", 5, "abcdefghijklmnop"] do
        %{body: body} = valid_payload()

        conn
        |> post(~p"/api/provision", Map.put(body, "id", id))
        |> assert_problem(422, :invalid, [
          not_a_uuid_entry(%{"pointer" => "#/id"})
        ])
      end

      assert Lightning.Repo.aggregate(Lightning.Projects.Project, :count) ==
               projects
    end

    @tag login_as: "superuser"
    test "a body that is JSON but not an object answers 400 malformed", %{
      conn: conn
    } do
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/provision", "[1, 2]")
      |> assert_problem(400, :malformed, [])
    end

    test "POST reads the project's id from the body only, never the query", %{
      conn: conn
    } do
      superuser = insert(:user, role: :superuser)

      existing =
        insert(:project,
          name: "a",
          project_users: [%{user_id: superuser.id, role: :owner}]
        )

      superuser = assign_bearer(conn, superuser)
      fresh = Ecto.UUID.generate()

      for id <- [existing.id, fresh, "bad"] do
        superuser
        |> post(~p"/api/provision?#{%{id: id}}", %{"name" => "x"})
        |> assert_problem(422, :invalid, [
          %{
            "pointer" => "#/id",
            "code" => "required",
            "detail" => "can't be blank"
          }
        ])
      end

      assert Repo.reload!(existing).name == "a"
      refute Repo.get(Lightning.Projects.Project, fresh)
    end

    test "GET yaml without an id names the parameter", %{conn: conn} do
      conn
      |> get(~p"/api/provision/yaml")
      |> assert_problem(400, :invalid_parameter, [
        %{
          "parameter" => "id",
          "code" => "required",
          "detail" => "can't be blank"
        }
      ])
    end

    test "no answer quotes a value planted in the project credentials and channels of a document",
         %{
           conn: conn,
           project: project,
           user: user
         } do
      %{body: body} = valid_payload(project.id)

      body =
        body
        |> Map.merge(%{
          "project_credentials" => [
            %{"id" => Ecto.UUID.generate(), "name" => "x", "owner" => user.email}
          ],
          "channels" => [
            %{
              "id" => Ecto.UUID.generate(),
              "name" => "x",
              "destination_url" => "x",
              "destination_credential_id" => "x"
            }
          ]
        })
        |> plant_sentinel()
        |> put_in(["project_credentials", Access.at(0), "owner"], user.email)
        |> Map.put("id", project.id)

      conn
      |> post(~p"/api/provision", body)
      |> refute_sentinel()
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/project_credentials/0/name",
          "code" => "not_found",
          "detail" => "names nothing you can see"
        },
        %{
          "pointer" => "#/channels/0/destination_url",
          "code" => "format",
          "detail" => "must be either a http or https URL"
        },
        %{
          "pointer" => "#/workflows/0/edges/0/condition_type",
          "code" => "not_allowed",
          "detail" => "is invalid"
        },
        %{
          "pointer" => "#/workflows/0/edges/0/id",
          "code" => "format",
          "detail" => "is not a valid UUID"
        },
        %{
          "pointer" => "#/workflows/0/edges/0/source_job_id",
          "code" => "format",
          "detail" => "is not a valid UUID"
        },
        %{
          "pointer" => "#/workflows/0/edges/0/target_job_id",
          "code" => "format",
          "detail" => "is not a valid UUID"
        },
        %{
          "pointer" => "#/workflows/0/edges/0/target_job_id",
          "code" => "cycle",
          "detail" => "target_job_id must be different from source_job_id"
        },
        %{
          "pointer" => "#/workflows/0/triggers/0/id",
          "code" => "format",
          "detail" => "is not a valid UUID"
        },
        %{
          "pointer" => "#/workflows/0/jobs/0/id",
          "code" => "format",
          "detail" => "is not a valid UUID"
        },
        %{
          "pointer" => "#/workflows/0/jobs/1/id",
          "code" => "format",
          "detail" => "is not a valid UUID"
        },
        %{
          "pointer" => "#/workflows/0/jobs/1/id",
          "code" => "duplicate",
          "detail" => "names the same id as #/workflows/0/jobs/0"
        }
      ])
    end
  end
end
