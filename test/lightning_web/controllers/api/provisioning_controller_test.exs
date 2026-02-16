defmodule LightningWeb.API.ProvisioningControllerTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Lightning.Factories

  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Workflow
  alias LightningWeb.API.ProvisioningJSON

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

    test "returns a new empty project", %{
      conn: conn,
      user: user
    } do
      %{id: project_id, name: project_name} =
        insert(:project,
          project_users: [%{user_id: user.id}]
        )

      conn = get(conn, ~p"/api/provision/#{project_id}")
      response = json_response(conn, 200)

      assert %{
               "id" => ^project_id,
               "name" => ^project_name,
               "workflows" => []
             } = response["data"]
    end

    test "returns a project with collections", %{
      conn: conn,
      user: user
    } do
      %{id: project_id, name: project_name} =
        project =
        insert(:project,
          project_users: [%{user_id: user.id}]
        )

      %{id: collection_id, name: collection_name} =
        insert(:collection, project: project)

      conn = get(conn, ~p"/api/provision/#{project_id}")
      response = json_response(conn, 200)

      assert %{
               "id" => ^project_id,
               "name" => ^project_name,
               "workflows" => [],
               "collections" => collections_resp
             } = response["data"]

      assert collections_resp == [
               %{"id" => collection_id, "name" => collection_name}
             ]
    end

    test "returns a non empty project without credentials", %{
      conn: conn,
      user: user
    } do
      %{id: project_id, name: project_name} =
        project =
        insert(:project,
          project_users: [%{user_id: user.id}]
        )

      project_credential =
        insert(:project_credential,
          credential: %{
            name: "test credential",
            body: %{"username" => "quux", "password" => "immasecret"},
            user_id: user.id
          },
          project: project
        )

      %{
        triggers: [%{id: trigger_id}],
        edges: [%{id: edge_1_id} = edge_1],
        jobs: [%{id: job_1_id} = job_1]
      } =
        workflow =
        insert(:simple_workflow, project: project, name: "Workflow123")

      %{id: job_2_id} =
        job_2 =
        insert(:job,
          workflow: workflow,
          name: "Second Step",
          adaptor: "@openfn/language-http@latest",
          body: "fn(state => state.references)",
          workflow: workflow,
          project_credential: project_credential
        )

      %{id: edge_2_id} =
        edge_2 =
        insert(:edge,
          workflow: workflow,
          source_job: job_1,
          target_job: job_2,
          condition_type: :js_expression,
          condition_label: "sick",
          condition_expression: "data.illness === true"
        )

      %{
        "edges" => [edge_1_json, edge_2_json],
        "jobs" => [_job_1, job_2_json],
        "triggers" => [trigger_json]
      } =
        workflow_json =
        workflow
        |> Map.merge(%{jobs: [job_1, job_2], edges: [edge_1, edge_2]})
        |> ProvisioningJSON.as_json()
        |> Jason.encode!()
        |> Jason.decode!()

      assert %{
               "id" => ^edge_1_id,
               "condition_type" => "always",
               "source_trigger_id" => ^trigger_id,
               "target_job_id" => ^job_1_id,
               "enabled" => true
             } =
               edge_1_json

      refute Map.has_key?(edge_1_json, "source_job_id")
      refute Map.has_key?(edge_1_json, "condition_label")
      refute Map.has_key?(edge_1_json, "condition_expression")

      assert %{
               "id" => ^edge_2_id,
               "condition_type" => "js_expression",
               "condition_label" => "sick",
               "condition_expression" => "data.illness === true",
               "source_job_id" => ^job_1_id,
               "target_job_id" => ^job_2_id,
               "enabled" => true
             } =
               edge_2_json

      assert Map.has_key?(job_2_json, "project_credential_id")

      assert %{
               "id" => ^job_2_id,
               "name" => "Second Step",
               "adaptor" => "@openfn/language-http@latest",
               "body" => "fn(state => state.references)"
             } = job_2_json

      assert %{
               "id" => ^trigger_id,
               "type" => "webhook",
               "enabled" => true
             } = trigger_json

      conn = get(conn, ~p"/api/provision/#{project_id}")
      response = json_response(conn, 200)

      assert %{
               "id" => ^project_id,
               "name" => ^project_name,
               "workflows" => [^workflow_json]
             } = response["data"]
    end

    test "returns a non empty project without credentials for support user", %{
      conn: conn,
      user: user
    } do
      _user = Repo.update!(Ecto.Changeset.change(user, %{support_user: true}))

      %{id: project_id, name: project_name} =
        project =
        insert(:project,
          allow_support_access: true,
          project_users: [%{user: build(:user), role: :owner}]
        )

      project_credential =
        insert(:project_credential,
          credential: %{
            name: "test credential",
            body: %{"username" => "quux", "password" => "immasecret"},
            user_id: user.id
          },
          project: project
        )

      %{
        triggers: [%{id: trigger_id}],
        edges: [%{id: edge_1_id} = edge_1],
        jobs: [%{id: job_1_id} = job_1]
      } =
        workflow =
        insert(:simple_workflow, project: project, name: "Workflow123")

      %{id: job_2_id} =
        job_2 =
        insert(:job,
          workflow: workflow,
          name: "Second Step",
          adaptor: "@openfn/language-http@latest",
          body: "fn(state => state.references)",
          workflow: workflow,
          project_credential: project_credential
        )

      %{id: edge_2_id} =
        edge_2 =
        insert(:edge,
          workflow: workflow,
          source_job: job_1,
          target_job: job_2,
          condition_type: :js_expression,
          condition_label: "sick",
          condition_expression: "data.illness === true"
        )

      %{
        "edges" => [edge_1_json, edge_2_json],
        "jobs" => [_job_1, job_2_json],
        "triggers" => [trigger_json]
      } =
        workflow_json =
        workflow
        |> Map.merge(%{jobs: [job_1, job_2], edges: [edge_1, edge_2]})
        |> ProvisioningJSON.as_json()
        |> Jason.encode!()
        |> Jason.decode!()

      assert %{
               "id" => ^edge_1_id,
               "condition_type" => "always",
               "source_trigger_id" => ^trigger_id,
               "target_job_id" => ^job_1_id,
               "enabled" => true
             } =
               edge_1_json

      refute Map.has_key?(edge_1_json, "source_job_id")
      refute Map.has_key?(edge_1_json, "condition_label")
      refute Map.has_key?(edge_1_json, "condition_expression")

      assert %{
               "id" => ^edge_2_id,
               "condition_type" => "js_expression",
               "condition_label" => "sick",
               "condition_expression" => "data.illness === true",
               "source_job_id" => ^job_1_id,
               "target_job_id" => ^job_2_id,
               "enabled" => true
             } =
               edge_2_json

      assert Map.has_key?(job_2_json, "project_credential_id")

      assert %{
               "id" => ^job_2_id,
               "name" => "Second Step",
               "adaptor" => "@openfn/language-http@latest",
               "body" => "fn(state => state.references)"
             } = job_2_json

      assert %{
               "id" => ^trigger_id,
               "type" => "webhook",
               "enabled" => true
             } = trigger_json

      conn = get(conn, ~p"/api/provision/#{project_id}")
      response = json_response(conn, 200)

      assert %{
               "id" => ^project_id,
               "name" => ^project_name,
               "workflows" => [^workflow_json]
             } = response["data"]
    end

    test "returns a project without deleted workflows", %{
      conn: conn,
      user: user
    } do
      %{id: project_id, name: project_name} =
        project =
        insert(:project,
          project_users: [%{user_id: user.id}]
        )

      _deleted_workflow =
        insert(:workflow,
          project: project,
          name: "Deleted workflow",
          deleted_at: DateTime.utc_now()
        )

      existing_workflow =
        insert(:workflow,
          project: project,
          name: "Existing workflow",
          deleted_at: nil
        )

      conn = get(conn, ~p"/api/provision/#{project_id}")
      response = json_response(conn, 200)

      assert %{
               "id" => ^project_id,
               "name" => ^project_name,
               "workflows" => [workflow_resp]
             } = response["data"]

      assert workflow_resp["id"] == existing_workflow.id
    end

    test "includes version_history in workflow response", %{
      conn: conn,
      user: user
    } do
      %{id: project_id} =
        project =
        insert(:project,
          project_users: [%{user_id: user.id}]
        )

      workflow =
        insert(:simple_workflow, project: project, name: "Test Workflow")

      # Record some version history
      {:ok, workflow} =
        Lightning.WorkflowVersions.record_version(
          workflow,
          "aabbccddeeff",
          "app"
        )

      {:ok, _workflow} =
        Lightning.WorkflowVersions.record_version(
          workflow,
          "112233445566",
          "cli"
        )

      conn = get(conn, ~p"/api/provision/#{project_id}")
      response = json_response(conn, 200)

      assert %{"workflows" => [workflow_json]} = response["data"]
      assert workflow_json["id"] == workflow.id

      # Verify version_history is included and has the expected values
      assert workflow_json["version_history"] == [
               "app:aabbccddeeff",
               "cli:112233445566"
             ]
    end

    test "returns a project only with the specified snapshots", %{
      conn: conn,
      user: user
    } do
      %{id: project_id, name: project_name} =
        project =
        insert(:project,
          project_users: [%{user_id: user.id}]
        )

      workflow_1 =
        insert(:simple_workflow,
          project: project,
          name: "workflow 1"
        )

      {:ok, snapshot_1} = Snapshot.create(workflow_1)

      {:ok, updated_workflow_1} =
        workflow_1
        |> Ecto.Changeset.change(%{name: "updated-workflow-name"})
        |> Lightning.Repo.update()

      workflow_2 =
        insert(:simple_workflow,
          project: project,
          name: "workflow 2"
        )

      {:ok, snapshot_2} = Snapshot.create(workflow_2)

      conn =
        get(conn, ~p"/api/provision/#{project_id}", snapshots: [snapshot_1.id])

      response = json_response(conn, 200)

      assert %{
               "id" => ^project_id,
               "name" => ^project_name,
               "workflows" => [workflow_resp]
             } = response["data"]

      # Only the first workflow is returned because its snapshot was specified
      assert workflow_resp["id"] == workflow_1.id
      # The name of the workflow is the original name, not the updated name
      assert workflow_resp["name"] == workflow_1.name
      assert updated_workflow_1.name != workflow_1.name

      # Now we specify both snapshots
      conn =
        get(conn, ~p"/api/provision/#{project_id}",
          snapshots: [snapshot_1.id, snapshot_2.id]
        )

      response = json_response(conn, 200)

      assert %{"workflows" => workflows} = response["data"]
      assert Enum.count(workflows) == 2
    end

    test "returns a project with kafka trigger workflow", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user_id: user.id}])

      trigger =
        build(:trigger,
          type: :kafka,
          kafka_configuration: %{
            hosts: [["localhost", "9092"]],
            topics: ["dummy"],
            initial_offset_reset_policy: "earliest"
          }
        )

      job =
        build(:job,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      %{triggers: [%{id: trigger_id}]} =
        build(:workflow,
          project: project,
          name: "Workflow123"
        )
        |> with_trigger(trigger)
        |> with_job(job)
        |> with_edge({trigger, job}, condition_type: :always)
        |> insert()

      conn = get(conn, ~p"/api/provision/#{project.id}")
      response = json_response(conn, 200)

      assert %{
               "workflows" => [
                 %{
                   "triggers" => [
                     %{
                       "type" => "kafka",
                       "id" => ^trigger_id,
                       "kafka_configuration" => exported_kafka_config
                     }
                   ]
                 }
               ]
             } = response["data"]

      assert match?(
               %{
                 "hosts" => [["localhost", "9092"]],
                 "topics" => ["dummy"],
                 "initial_offset_reset_policy" => "earliest"
               },
               exported_kafka_config
             )
    end

    test "returns a project if user has owner access", %{
      conn: conn,
      user: user
    } do
      %{id: project_id, name: project_name} =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      conn = get(conn, ~p"/api/provision/#{project_id}")
      response = json_response(conn, 200)

      assert %{
               "id" => ^project_id,
               "name" => ^project_name,
               "workflows" => workflows
             } = response["data"]

      assert workflows |> Enum.all?(&match?(%{"project_id" => ^project_id}, &1))
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

    test "returns a 200 if a valid repo conenction token is provided for the project state" do
      project = insert(:project)

      repo_connection = insert(:project_repo_connection, project: project)

      conn =
        Plug.Conn.put_req_header(
          build_conn(),
          "authorization",
          "Bearer #{repo_connection.access_token}"
        )

      response = get(conn, ~p"/api/provision/#{project.id}")
      assert response.status == 200
    end

    test "returns a 200 if a valid repo conenction token is provided for the project yaml" do
      project = insert(:project)

      repo_connection = insert(:project_repo_connection, project: project)

      conn =
        Plug.Conn.put_req_header(
          build_conn(),
          "authorization",
          "Bearer #{repo_connection.access_token}"
        )

      response = get(conn, ~p"/api/provision/yaml?#{%{id: project.id}}")
      assert response.status == 200
    end

    test "returns valid project yaml for snapshots provided" do
      project = insert(:project)
      repo_connection = insert(:project_repo_connection, project: project)

      workflow_1 =
        insert(:simple_workflow,
          project: project,
          name: "workflow 1"
        )

      {:ok, snapshot_1} = Snapshot.create(workflow_1)

      {:ok, updated_workflow_1} =
        workflow_1
        |> Ecto.Changeset.change(%{name: "updated-workflow-name"})
        |> Lightning.Repo.update()

      workflow_2 =
        insert(:simple_workflow,
          project: project,
          name: "workflow 2"
        )

      {:ok, snapshot_2} = Snapshot.create(workflow_2)

      conn =
        Plug.Conn.put_req_header(
          build_conn(),
          "authorization",
          "Bearer #{repo_connection.access_token}"
        )

      response =
        get(
          conn,
          ~p"/api/provision/yaml?#{%{id: project.id, snapshots: [snapshot_1.id]}}"
        )
        |> response(200)

      assert response =~ workflow_1.name
      refute response =~ updated_workflow_1.name
      refute response =~ workflow_2.name

      response =
        get(
          conn,
          ~p"/api/provision/yaml?#{%{id: project.id, snapshots: [snapshot_1.id, snapshot_2.id]}}"
        )
        |> response(200)

      assert response =~ workflow_1.name
      refute response =~ updated_workflow_1.name
      assert response =~ workflow_2.name
    end

    test "returns a 403 if an invalid repo conenction token is provided" do
      project_1 = insert(:project)
      project_2 = insert(:project)

      wrong_repo_connection =
        insert(:project_repo_connection, project: project_2)

      conn =
        Plug.Conn.put_req_header(
          build_conn(),
          "authorization",
          "Bearer #{wrong_repo_connection.access_token}"
        )

      conn = get(conn, ~p"/api/provision/#{project_1.id}")

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

    test "is forbidden for an invalid PRC access_token", %{conn: conn} do
      project = insert(:project)
      wrong_project = insert(:project)

      wrong_repo_connection =
        insert(:project_repo_connection, project: wrong_project)

      %{body: body} = valid_payload(project.id)

      conn =
        Plug.Conn.put_req_header(
          conn,
          "authorization",
          "Bearer #{wrong_repo_connection.access_token}"
        )

      response = post(conn, ~p"/api/provision", body)
      assert response.status == 403
    end

    test "fails with 403 when usage limiter returns an error", %{
      conn: conn
    } do
      %{id: project_id} = project = insert(:project)

      repo_connection =
        insert(:project_repo_connection, project: project)

      %{body: body} = valid_payload(project.id)

      conn =
        Plug.Conn.put_req_header(
          conn,
          "authorization",
          "Bearer #{repo_connection.access_token}"
        )

      error_text = "some error message"

      Lightning.Extensions.MockUsageLimiter
      |> Mox.expect(:limit_action, fn %{type: :api_provisioning},
                                      %{project_id: ^project_id} ->
        {:error, :disabled, %Lightning.Extensions.Message{text: error_text}}
      end)

      assert post(conn, ~p"/api/provision", body) |> json_response(403) ==
               %{"error" => error_text}
    end

    test "fails with a 422 on validation errors", %{conn: conn, user: user} do
      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      body = %{
        "id" => project.id,
        "name" => "",
        "workflows" => [
          %{"name" => "default"},
          %{"id" => Ecto.UUID.generate(), "name" => "Valid Workflow"}
        ]
      }

      conn = post(conn, ~p"/api/provision", body)
      response = json_response(conn, 422)

      assert response == %{
               "errors" => %{
                 "name" => ["This field can't be blank."],
                 "workflows" => %{
                   "default" => %{"id" => ["This field can't be blank."]}
                 }
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

      conn = post(conn, ~p"/api/provision", body)
      response = json_response(conn, 422)

      assert response == %{
               "errors" => %{
                 "workflows" => %{
                   "default" => %{
                     "jobs" => %{
                       "first-job" => %{
                         "id" => ["This field can't be blank."],
                         "body" => ["Code editor cannot be empty."]
                       },
                       "" => %{
                         "name" => ["Job name can't be blank."],
                         "id" => ["This field can't be blank."]
                       }
                     },
                     "id" => ["This field can't be blank."]
                   }
                 }
               }
             }

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

        conn = post(conn, ~p"/api/provision", body)
        response = json_response(conn, 422)

        assert response == %{
                 "errors" => %{
                   "workflows" => %{
                     "default" => %{
                       "edges" => %{
                         "#{trigger_type}->first-job" => %{
                           "condition_type" => ["This field can't be blank."]
                         }
                       }
                     }
                   }
                 }
               }
      end
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

    test "allows a valid PRC token to update an existing project", %{
      conn: conn
    } do
      project = insert(:project)

      repo_connection =
        insert(:project_repo_connection, project: project)

      %{body: body} = valid_payload(project.id)

      conn =
        Plug.Conn.put_req_header(
          conn,
          "authorization",
          "Bearer #{repo_connection.access_token}"
        )

      assert post(conn, ~p"/api/provision", body) |> json_response(201)
    end

    test "records workflow version with 'cli' source when workflow is created via provisioner",
         %{conn: conn, user: user} do
      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      %{body: body, workflow_id: workflow_id} = valid_payload(project.id)

      conn = post(conn, ~p"/api/provision", body)
      assert json_response(conn, 201)

      workflow = Lightning.Repo.get!(Workflow, workflow_id)
      version_history = Lightning.WorkflowVersions.history_for(workflow)

      assert length(version_history) == 1
      assert [version] = version_history
      assert String.starts_with?(version, "cli:")
    end

    test "records new workflow version when workflow is updated via provisioner",
         %{conn: conn, user: user} do
      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      # First provision - creates workflow
      %{body: body, workflow_id: workflow_id} = valid_payload(project.id)

      conn = post(conn, ~p"/api/provision", body)
      assert json_response(conn, 201)

      workflow = Lightning.Repo.get!(Workflow, workflow_id)
      initial_history = Lightning.WorkflowVersions.history_for(workflow)
      assert length(initial_history) == 1
      assert [initial_version] = initial_history
      assert String.starts_with?(initial_version, "cli:")

      # Update workflow by changing job body
      updated_body =
        body
        |> Map.update!("workflows", fn workflows ->
          Enum.at(workflows, 0)
          |> Map.update!("jobs", fn jobs ->
            Enum.map(jobs, fn job ->
              Map.put(job, "body", "console.log('updated');")
            end)
          end)
          |> then(fn workflow ->
            List.replace_at(workflows, 0, workflow)
          end)
        end)

      conn = post(conn, ~p"/api/provision", updated_body)
      assert json_response(conn, 201)

      workflow = Lightning.Repo.get!(Workflow, workflow_id)
      updated_history = Lightning.WorkflowVersions.history_for(workflow)

      # Due to squashing behavior, consecutive versions from same source replace each other
      # So we still have 1 version, but the hash should be different
      assert length(updated_history) == 1
      assert [updated_version] = updated_history
      assert String.starts_with?(updated_version, "cli:")

      # Verify the hash changed after the update
      refute initial_version == updated_version
    end

    test "does not create duplicate version when provisioning same workflow content",
         %{conn: conn, user: user} do
      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      # First provision - creates workflow
      %{body: body, workflow_id: workflow_id} = valid_payload(project.id)

      conn = post(conn, ~p"/api/provision", body)
      assert json_response(conn, 201)

      workflow = Lightning.Repo.get!(Workflow, workflow_id)
      initial_history = Lightning.WorkflowVersions.history_for(workflow)
      assert length(initial_history) == 1

      # Provision again with the exact same content
      conn = post(conn, ~p"/api/provision", body)
      assert json_response(conn, 201)

      workflow = Lightning.Repo.get!(Workflow, workflow_id)
      duplicate_history = Lightning.WorkflowVersions.history_for(workflow)

      # Should still have only 1 version since content didn't change
      assert length(duplicate_history) == 1
      assert duplicate_history == initial_history
    end

    test "handles provisioning with no workflow changes gracefully",
         %{conn: conn, user: user} do
      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      # Create a project with a workflow that has an initial version
      %{body: body, workflow_id: workflow_id} = valid_payload(project.id)

      # First provision to create the workflow
      conn = post(conn, ~p"/api/provision", body)
      assert json_response(conn, 201)

      # Get the workflow and its initial version history
      workflow = Lightning.Repo.get!(Workflow, workflow_id)
      initial_history = Lightning.WorkflowVersions.history_for(workflow)
      assert length(initial_history) == 1

      # Update only project metadata, keeping workflow unchanged
      updated_body = Map.put(body, "name", "updated-project-name")

      conn = post(conn, ~p"/api/provision", updated_body)
      assert json_response(conn, 201)

      # Verify version history unchanged since workflow content didn't change
      workflow = Lightning.Repo.get!(Workflow, workflow_id)
      version_history = Lightning.WorkflowVersions.history_for(workflow)
      assert version_history == initial_history

      # Verify project name was updated
      project = Lightning.Repo.get!(Lightning.Projects.Project, project.id)
      assert project.name == "updated-project-name"
    end

    test "returns 201 for an existing project with workflows marked for deletion",
         %{
           conn: conn
         } do
      project = insert(:project)

      _deleted_workflow =
        insert(:workflow,
          project: project,
          name: "Deleted workflow",
          deleted_at: DateTime.utc_now()
        )

      repo_connection =
        insert(:project_repo_connection, project: project)

      %{body: body} = valid_payload(project.id)

      conn =
        Plug.Conn.put_req_header(
          conn,
          "authorization",
          "Bearer #{repo_connection.access_token}"
        )

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

      workflow_ids = Enum.map(workflows, fn w -> w["id"] end)

      parent_project_ids =
        from(w in Workflow,
          where: w.id in ^workflow_ids
        )
        |> Repo.all()
        |> Enum.map(fn w -> w.project_id end)

      assert parent_project_ids |> Enum.all?(&match?(^project_id, &1)),
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
