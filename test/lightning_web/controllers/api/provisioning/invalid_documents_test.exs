defmodule LightningWeb.API.ProvisioningInvalidDocumentsTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProvisioningHelpers
  import LightningWeb.API.ProblemHelpers
  import Lightning.Factories

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "a document that breaks a rule" do
    setup [:assign_bearer_for_api]

    setup %{user: user} do
      %{
        project:
          insert(:project, project_users: [%{user_id: user.id, role: :owner}])
      }
    end

    test "a blank project name and a workflow without an id answer 422 required at each pointer",
         %{conn: conn, project: project} do
      body = %{
        "id" => project.id,
        "name" => "",
        "workflows" => [
          %{"name" => "default"},
          %{"id" => Ecto.UUID.generate(), "name" => "Valid Workflow"}
        ]
      }

      conn
      |> post(~p"/api/provision", body)
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/name",
          "code" => "required",
          "detail" => "can't be blank"
        },
        %{
          "pointer" => "#/workflows/0/id",
          "code" => "required",
          "detail" => "can't be blank"
        }
      ])
    end

    test "jobs missing an id, a name or a body answer 422 required at each pointer",
         %{conn: conn, project: project} do
      body = %{
        "id" => project.id,
        "name" => "test-project",
        "workflows" => [
          %{
            "name" => "default",
            "jobs" => [
              %{
                "name" => "first-job",
                "adaptor" => "@openfn/language-common@latest"
              },
              %{
                "adaptor" => "@openfn/language-common@latest",
                "body" => "console.log('hello world');"
              },
              %{
                "id" => Ecto.UUID.generate(),
                "name" => "valid job",
                "adaptor" => "@openfn/language-common@latest",
                "body" => "console.log('hello world');"
              }
            ]
          }
        ]
      }

      conn
      |> post(~p"/api/provision", body)
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/workflows/0/id",
          "code" => "required",
          "detail" => "can't be blank"
        },
        %{
          "pointer" => "#/workflows/0/jobs/0/id",
          "code" => "required",
          "detail" => "can't be blank"
        },
        %{
          "pointer" => "#/workflows/0/jobs/0/body",
          "code" => "required",
          "detail" => "job body can't be blank"
        },
        %{
          "pointer" => "#/workflows/0/jobs/1/id",
          "code" => "required",
          "detail" => "can't be blank"
        },
        %{
          "pointer" => "#/workflows/0/jobs/1/name",
          "code" => "required",
          "detail" => "job name can't be blank"
        }
      ])
    end

    test "an edge without a condition type answers 422 required, whatever its trigger's type",
         %{conn: conn, project: project} do
      job_id = Ecto.UUID.generate()
      trigger_id = Ecto.UUID.generate()

      for trigger_type <- ["cron", "webhook"] do
        body = %{
          "id" => project.id,
          "name" => "test-project",
          "workflows" => [
            %{
              "id" => Ecto.UUID.generate(),
              "name" => "default",
              "jobs" => [
                %{
                  "id" => job_id,
                  "name" => "first-job",
                  "adaptor" => "@openfn/language-common@latest",
                  "body" => "console.log('hello world')"
                }
              ],
              "triggers" => [
                %{"id" => trigger_id, "type" => trigger_type}
              ],
              "edges" => [
                %{
                  "id" => Ecto.UUID.generate(),
                  "source_trigger_id" => trigger_id,
                  "target_job_id" => job_id
                }
              ]
            }
          ]
        }

        conn
        |> post(~p"/api/provision", body)
        |> assert_problem(422, :invalid, [
          %{
            "pointer" => "#/workflows/0/edges/0/condition_type",
            "code" => "required",
            "detail" => "can't be blank"
          }
        ])
      end
    end

    test "a key the server doesn't accept answers 422 unknown_key at its own pointer",
         %{conn: conn, project: project} do
      %{body: body} = valid_payload(project.id)

      body =
        body
        |> Map.put("foo", "bar")
        |> put_in(
          ["workflows", Access.at(0), "triggers", Access.at(0), "project_id"],
          "anything"
        )

      conn
      |> post(~p"/api/provision", body)
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/foo",
          "code" => "unknown_key",
          "detail" => "is not accepted"
        },
        %{
          "pointer" => "#/workflows/0/triggers/0/project_id",
          "code" => "unknown_key",
          "detail" => "is not accepted"
        }
      ])
    end

    test "a credential name the caller can't see answers 422 not_found at that link's name",
         %{conn: conn, project: project, user: user} do
      known = insert(:credential, name: "known", user: user)
      %{body: body} = valid_payload(project.id)

      body =
        Map.put(body, "project_credentials", [
          %{
            "id" => Ecto.UUID.generate(),
            "name" => known.name,
            "owner" => user.email
          },
          %{
            "id" => Ecto.UUID.generate(),
            "name" => "missing",
            "owner" => user.email
          }
        ])

      conn
      |> post(~p"/api/provision", body)
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/project_credentials/1/name",
          "code" => "not_found",
          "detail" => "names nothing you can see"
        }
      ])
    end

    test "a job marked for deletion keeps its place, so later errors point past it",
         %{conn: conn, project: project} do
      %{body: body, first_job_id: first_job_id} = valid_payload(project.id)

      conn |> post(~p"/api/provision", body) |> json_response(201)

      body =
        body
        |> remove_job_from_document(first_job_id)
        |> update_in(["workflows", Access.at(0), "jobs"], fn jobs ->
          jobs ++ [%{"id" => Ecto.UUID.generate(), "body" => "fn(s => s)"}]
        end)

      conn
      |> post(~p"/api/provision", body)
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/workflows/0/jobs/2/name",
          "code" => "required",
          "detail" => "job name can't be blank"
        }
      ])

      assert Lightning.Repo.get(Lightning.Workflows.Job, first_job_id),
             "a refused document deleted a job"
    end

    test "two jobs with one name answer 422 invalid, with one taken entry", %{
      conn: conn,
      project: project
    } do
      %{body: body} = valid_payload(project.id)

      body =
        update_in(body, ["workflows", Access.at(0), "jobs", Access.at(1)], fn
          job -> Map.put(job, "name", "first-job")
        end)

      conn
      |> post(~p"/api/provision", body)
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/workflows/0/jobs/1/name",
          "code" => "taken",
          "detail" => "job name has already been taken"
        }
      ])
    end

    test "a project credential, collection or channel id another project uses answers 422 invalid with a taken entry at its position",
         %{conn: conn, project: project, user: user} do
      insert(:credential, user: user, name: "mine")
      %{body: body} = valid_payload(project.id)

      for {key, taken_id, item} <- [
            {"project_credentials", insert(:project_credential).id,
             fn id, _name ->
               %{"id" => id, "name" => "mine", "owner" => user.email}
             end},
            {"collections", insert(:collection).id,
             fn id, name -> %{"id" => id, "name" => name} end},
            {"channels", insert(:channel).id,
             fn id, name ->
               %{
                 "id" => id,
                 "name" => name,
                 "destination_url" => "https://example.com/#{name}"
               }
             end}
          ] do
        body =
          Map.put(body, key, [
            item.(Ecto.UUID.generate(), "first"),
            item.(taken_id, "second")
          ])

        conn
        |> post(~p"/api/provision", body)
        |> assert_problem(422, :invalid, [
          %{
            "pointer" => "#/#{key}/1/id",
            "code" => "taken",
            "detail" => "has already been taken"
          }
        ])
      end
    end
  end
end
