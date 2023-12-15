defmodule LightningWeb.API.ProvisioningControllerTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Lightning.Factories

  alias Lightning.Workflows.Workflow

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "without a token" do
    test "get returns a 401", %{conn: conn} do
      conn = get(conn, Routes.api_project_path(conn, :index))
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end

    test "post returns a 401", %{conn: conn} do
      body = %{"id" => "abc123", "workflows" => [%{"name" => "default"}]}

      conn = post(conn, ~p"/api/provision", body)
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "get (with an API token)" do
    setup [:assign_bearer_for_api]

    test "returns a project if user has owner access", %{
      conn: conn,
      user: user
    } do
      %{id: project_id, name: project_name} =
        project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      conn = get(conn, ~p"/api/provision/#{project.id}")
      response = json_response(conn, 200)

      assert %{
               "id" => ^project_id,
               "name" => ^project_name,
               "workflows" => workflows
             } = response["data"]

      assert workflows |> Enum.all?(&match?(%{"project_id" => ^project_id}, &1)),
             "All workflows should belong to the same project"
    end

    test "returns a 200 if user has admin access", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :admin}]
        )

      response = get(conn, ~p"/api/provision/#{project.id}")
      assert response.status == 200
    end

    test "returns a 200 if user has editor access", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :editor}]
        )

      response = get(conn, ~p"/api/provision/#{project.id}")
      assert response.status == 200
    end

    test "returns a 200 if user has viewer access", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :viewer}]
        )

      response = get(conn, ~p"/api/provision/#{project.id}")
      assert response.status == 200
    end

    test "returns a 403 if user does not have access", %{
      conn: conn
    } do
      %{id: project_id} = insert(:project)

      conn = get(conn, ~p"/api/provision/#{project_id}")
      response = json_response(conn, 403)

      assert response == %{"error" => "Forbidden"}
    end
  end

  describe "post (with an API token)" do
    setup [:assign_bearer_for_api]

    test "is forbidden for a viewer", %{conn: conn, user: user} do
      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :viewer}]
        )

      body = %{
        "id" => project.id,
        "workflows" => [%{"name" => "default"}]
      }

      response = post(conn, ~p"/api/provision", body)
      assert response.status == 403
    end

    test "is forbidden for an editor", %{conn: conn, user: user} do
      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :editor}]
        )

      body = %{
        "id" => project.id,
        "workflows" => [%{"name" => "default"}]
      }

      response = post(conn, ~p"/api/provision", body)
      assert response.status == 403
    end

    test "fails with a 422 on validation errors", %{conn: conn, user: user} do
      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      body = %{
        "id" => project.id,
        "name" => "",
        "workflows" => [%{"name" => "default"}]
      }

      conn = post(conn, ~p"/api/provision", body)
      response = json_response(conn, 422)

      assert response == %{
               "errors" => %{
                 "name" => ["This field can't be blank."],
                 "workflows" => [%{"id" => ["This field can't be blank."]}]
               }
             }

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
              }
            ]
          }
        ]
      }

      conn = post(conn, ~p"/api/provision", body)
      response = json_response(conn, 422)

      assert response == %{
               "errors" => %{
                 "workflows" => [
                   %{
                     "jobs" => [
                       %{
                         "id" => ["This field can't be blank."],
                         "body" => ["This field can't be blank."]
                       },
                       %{
                         "name" => ["This field can't be blank."],
                         "id" => ["This field can't be blank."]
                       }
                     ],
                     "id" => ["This field can't be blank."]
                   }
                 ]
               }
             }
    end

    test "allows an owner to update an existing project", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      %{
        project_id: project_id,
        body: body,
        second_job_id: second_job_id
      } = valid_payload(project.id)

      conn = post(conn, ~p"/api/provision", body)
      response = json_response(conn, 201)

      assert %{
               "id" => ^project_id,
               "name" => "test-project",
               "workflows" => [_]
             } = response["data"]

      # - - -
      third_job_id = Ecto.UUID.generate()

      body =
        body
        |> Map.put("name", "test-project-renamed")
        |> add_job_to_document(%{
          "id" => third_job_id,
          "name" => "third-job",
          "adaptor" => "@openfn/language-common@latest",
          "body" => "console.log('hello world');"
        })

      conn = post(conn, ~p"/api/provision", body)
      response = json_response(conn, 201)

      assert %{
               "id" => ^project_id,
               "name" => "test-project-renamed",
               "workflows" => workflows
             } = response["data"]

      workflow_job_ids =
        workflows |> Enum.at(0) |> Map.get("jobs") |> Enum.into([], & &1["id"])

      assert third_job_id in workflow_job_ids

      body = body |> remove_job_from_document(second_job_id)

      conn = post(conn, ~p"/api/provision", body)
      response = json_response(conn, 201)

      assert %{
               "id" => ^project_id,
               "name" => "test-project-renamed",
               "workflows" => workflows
             } = response["data"]

      workflow_job_ids =
        workflows |> Enum.at(0) |> Map.get("jobs") |> Enum.into([], & &1["id"])

      refute second_job_id in workflow_job_ids
      assert third_job_id in workflow_job_ids

      assert workflows |> Enum.at(0) |> Map.get("edges") == [],
             "The edge associated with the deleted job should be removed"
    end

    test "allows an admin to update an existing project", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :admin}]
        )

      %{body: body} = valid_payload(project.id)

      assert post(conn, ~p"/api/provision", body) |> json_response(201)
    end

    @tag login_as: "superuser"
    test "allows a superuser to create a new project", %{conn: conn} do
      %{
        body: body,
        project_id: project_id,
        first_job_id: first_job_id,
        second_job_id: second_job_id,
        trigger_id: trigger_id,
        workflow_id: workflow_id,
        job_edge_id: job_edge_id
      } = valid_payload()

      conn = post(conn, ~p"/api/provision", body)
      response = json_response(conn, 201)

      assert %{
               "id" => ^project_id,
               "name" => "test-project",
               "workflows" => workflows
             } = response["data"]

      project = Lightning.Projects.get_project!(project_id)

      assert project.name == "test-project"

      assert workflows |> Enum.all?(&match?(%{"project_id" => ^project_id}, &1)),
             "All workflows should belong to the same project"

      workflow =
        from(w in Workflow,
          preload: [:jobs, :triggers, :edges],
          where: w.id == ^workflow_id
        )
        |> Lightning.Repo.one!()

      assert workflow.name == "default"
      assert workflow.edges |> MapSet.new(& &1.id) == MapSet.new([job_edge_id])

      assert workflow.jobs |> MapSet.new(& &1.id) ==
               MapSet.new([first_job_id, second_job_id])

      assert workflow.triggers |> MapSet.new(& &1.id) == MapSet.new([trigger_id])
    end

    test "doesn't let a normal user create a new project", %{conn: conn} do
      %{body: body} = valid_payload()

      response = post(conn, ~p"/api/provision", body)
      assert response.status == 403
    end
  end

  defp valid_payload(project_id \\ nil) do
    project_id = project_id || Ecto.UUID.generate()
    first_job_id = Ecto.UUID.generate()
    second_job_id = Ecto.UUID.generate()
    trigger_id = Ecto.UUID.generate()
    workflow_id = Ecto.UUID.generate()
    job_edge_id = Ecto.UUID.generate()

    body = %{
      "id" => project_id,
      "name" => "test-project",
      "workflows" => [
        %{
          "id" => workflow_id,
          "name" => "default",
          "jobs" => [
            %{
              "id" => first_job_id,
              "name" => "first-job",
              "adaptor" => "@openfn/language-common@latest",
              "body" => "console.log('hello world');"
            },
            %{
              "id" => second_job_id,
              "name" => "second-job",
              "adaptor" => "@openfn/language-common@latest",
              "body" => "console.log('hello world');"
            }
          ],
          "triggers" => [
            %{
              "id" => trigger_id
            }
          ],
          "edges" => [
            %{
              "id" => job_edge_id,
              "source_job_id" => first_job_id,
              "condition_type" => "on_job_success",
              "target_job_id" => second_job_id
            }
          ]
        }
      ]
    }

    %{
      body: body,
      project_id: project_id,
      workflow_id: workflow_id,
      first_job_id: first_job_id,
      second_job_id: second_job_id,
      trigger_id: trigger_id,
      job_edge_id: job_edge_id
    }
  end

  defp add_job_to_document(document, job_params) do
    document
    |> Map.update!("workflows", fn workflows ->
      Enum.at(workflows, 0)
      |> Map.update!("jobs", fn jobs ->
        [job_params | jobs]
      end)
      |> then(fn workflow ->
        List.replace_at(workflows, 0, workflow)
      end)
    end)
  end

  defp remove_job_from_document(document, id) do
    document
    |> Map.update!("workflows", fn workflows ->
      Enum.at(workflows, 0)
      |> Map.update!("jobs", fn jobs ->
        jobs
        |> Enum.map(fn job ->
          if job["id"] == id do
            Map.put(job, "delete", true)
          else
            job
          end
        end)
      end)
      |> then(fn workflow ->
        List.replace_at(workflows, 0, workflow)
      end)
    end)
  end
end
