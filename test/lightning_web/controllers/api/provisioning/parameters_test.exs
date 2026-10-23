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

    test "a project id in the body that isn't a UUID is not found", %{
      conn: conn
    } do
      %{body: body} = valid_payload("not-a-uuid")

      conn
      |> post(~p"/api/provision", body)
      |> assert_problem(404, :not_found, [])
    end

    test "GET answers an id that isn't there, or a yaml id that isn't a UUID, as not found",
         %{conn: conn} do
      for path <- [
            ~p"/api/provision/#{Ecto.UUID.generate()}",
            ~p"/api/provision/yaml?#{%{id: Ecto.UUID.generate()}}",
            ~p"/api/provision/yaml?#{%{id: "not-a-uuid"}}"
          ] do
        conn |> get(path) |> assert_problem(404, :not_found, [])
      end
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
