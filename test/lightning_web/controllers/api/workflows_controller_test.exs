defmodule LightningWeb.API.WorkflowsControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Lightning.WorkflowsFixtures
  import Phoenix.LiveViewTest

  alias Lightning.Extensions.Message
  alias Lightning.Workflows
  alias Lightning.Workflows.Presence

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn}
  end

  describe "index" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "lists workflows for projects I have access to", %{
      conn: conn,
      project: project
    } do
      workflow1 = insert(:workflow, project: project, name: "Workflow A")
      insert(:trigger, workflow: workflow1)
      insert(:job, workflow: workflow1)

      workflow2 = insert(:workflow, project: project, name: "Workflow B")
      insert(:trigger, workflow: workflow2)

      # Create a workflow in another project (should not be accessible)
      other_project = insert(:project)
      other_workflow = insert(:workflow, project: other_project)
      insert(:trigger, workflow: other_workflow)

      conn = get(conn, ~p"/api/workflows")

      response = json_response(conn, 200)

      assert length(response["workflows"]) == 2
      assert %{"errors" => %{}} = response

      workflow_ids = Enum.map(response["workflows"], & &1["id"])
      assert workflow1.id in workflow_ids
      assert workflow2.id in workflow_ids
      refute other_workflow.id in workflow_ids
    end

    test "filters workflows by project_id query parameter", %{
      conn: conn,
      user: user
    } do
      project1 =
        insert(:project, project_users: [%{user: user, role: :owner}])

      project2 =
        insert(:project, project_users: [%{user: user, role: :owner}])

      workflow1 = insert(:workflow, project: project1, name: "P1 Workflow")
      insert(:trigger, workflow: workflow1)

      workflow2 = insert(:workflow, project: project2, name: "P2 Workflow")
      insert(:trigger, workflow: workflow2)

      conn = get(conn, ~p"/api/workflows?project_id=#{project1.id}")

      response = json_response(conn, 200)

      assert length(response["workflows"]) == 1
      assert List.first(response["workflows"])["id"] == workflow1.id
    end

    test "nested route: lists workflows for specific project", %{
      conn: conn,
      user: user
    } do
      project1 =
        insert(:project, project_users: [%{user: user, role: :owner}])

      project2 =
        insert(:project, project_users: [%{user: user, role: :owner}])

      workflow1 = insert(:workflow, project: project1, name: "P1 Workflow")
      insert(:trigger, workflow: workflow1)

      workflow2 = insert(:workflow, project: project2, name: "P2 Workflow")
      insert(:trigger, workflow: workflow2)

      conn = get(conn, ~p"/api/projects/#{project1.id}/workflows")

      response = json_response(conn, 200)

      assert length(response["workflows"]) == 1
      assert List.first(response["workflows"])["id"] == workflow1.id
      refute Enum.any?(response["workflows"], &(&1["id"] == workflow2.id))
    end

    test "returns workflows with jobs, triggers, and edges", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project, name: "Full Workflow")
      trigger = insert(:trigger, workflow: workflow, type: :webhook)
      job = insert(:job, workflow: workflow)

      insert(:edge,
        workflow: workflow,
        source_trigger: trigger,
        target_job: job,
        condition_type: :always
      )

      conn = get(conn, ~p"/api/workflows")

      response = json_response(conn, 200)

      assert [wf] = response["workflows"]
      assert wf["id"] == workflow.id
      assert wf["name"] == "Full Workflow"

      assert length(wf["triggers"]) == 1
      assert List.first(wf["triggers"])["id"] == trigger.id

      assert length(wf["jobs"]) == 1
      assert List.first(wf["jobs"])["id"] == job.id

      assert length(wf["edges"]) == 1
    end

    test "returns exact workflow JSON for nested route", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:simple_workflow, name: "exact-check", project: project)

      conn = get(conn, ~p"/api/projects/#{project.id}/workflows")

      assert json_response(conn, 200) == %{
               "errors" => %{},
               "workflows" => [encode_decode(workflow)]
             }
    end

    test "returns 401 for project user cannot access", %{conn: conn} do
      other_project = insert(:project)

      conn = get(conn, ~p"/api/projects/#{other_project.id}/workflows")

      assert json_response(conn, 401)
    end

    test "returns 401 without a token" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/workflows")

      assert %{"error" => "Unauthorized"} == json_response(conn, 401)
    end

    test "returns 401 with an invalid token" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> Plug.Conn.put_req_header("authorization", "Bearer InvalidToken")
        |> get(~p"/api/workflows")

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end

    test "returns 401 with a run token instead of API token" do
      workflow = insert(:simple_workflow)
      workorder = insert(:workorder, dataclip: insert(:dataclip))

      run =
        insert(:run,
          work_order: workorder,
          dataclip: workorder.dataclip,
          starting_trigger: workflow.triggers |> hd()
        )

      token = Lightning.Workers.generate_run_token(run)

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> assign_bearer(token)
        |> get(~p"/api/projects/#{workflow.project_id}/workflows/#{workflow.id}")

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "show" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "returns a single workflow by id", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project, name: "My Workflow")
      trigger = insert(:trigger, workflow: workflow, type: :webhook)
      job = insert(:job, workflow: workflow, name: "Step One")

      insert(:edge,
        workflow: workflow,
        source_trigger: trigger,
        target_job: job,
        condition_type: :always
      )

      conn = get(conn, ~p"/api/workflows/#{workflow}")

      response = json_response(conn, 200)

      assert %{"workflow" => wf, "errors" => %{}} = response
      assert wf["id"] == workflow.id
      assert wf["name"] == "My Workflow"
      assert wf["project_id"] == project.id
      assert length(wf["triggers"]) == 1
      assert length(wf["jobs"]) == 1
      assert length(wf["edges"]) == 1
    end

    test "returns a workflow via nested project route", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project, name: "Nested Show")
      insert(:trigger, workflow: workflow)

      conn =
        get(conn, ~p"/api/projects/#{project.id}/workflows/#{workflow}")

      response = json_response(conn, 200)

      assert %{"workflow" => wf, "errors" => %{}} = response
      assert wf["id"] == workflow.id
      assert wf["name"] == "Nested Show"
    end

    test "returns exact workflow JSON for nested route", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:simple_workflow, project: project)

      conn =
        get(conn, ~p"/api/projects/#{project.id}/workflows/#{workflow.id}")

      assert json_response(conn, 200) == %{
               "errors" => %{},
               "workflow" => encode_decode(workflow)
             }
    end

    test "returns 404 for non-existent workflow", %{conn: conn} do
      conn = get(conn, ~p"/api/workflows/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)
    end

    test "returns 401 for workflow in project user cannot access", %{
      conn: conn
    } do
      other_project = insert(:project)

      other_workflow =
        insert(:workflow, project: other_project, name: "Secret")

      insert(:trigger, workflow: other_workflow)

      conn = get(conn, ~p"/api/workflows/#{other_workflow}")

      assert json_response(conn, 401)
    end

    test "returns 400 for project_id mismatch on nested route", %{
      conn: conn,
      user: user,
      project: project
    } do
      other_project =
        insert(:project, project_users: [%{user: user, role: :owner}])

      workflow = insert(:workflow, project: project, name: "Wrong Project")
      insert(:trigger, workflow: workflow)

      conn =
        get(
          conn,
          ~p"/api/projects/#{other_project.id}/workflows/#{workflow}"
        )

      response = json_response(conn, 400)
      assert response["error"] == "Bad Request"
    end

    test "returns 422 for invalid project_id", %{conn: conn, project: project} do
      workflow = insert(:workflow, project: project)
      insert(:trigger, workflow: workflow)

      conn = get(conn, ~p"/api/projects/foo/workflows/#{workflow.id}")

      assert %{
               "errors" => %{"workflow" => ["Id foo should be a UUID."]},
               "id" => nil
             } == json_response(conn, 422)
    end

    test "returns 401 without a token" do
      %{id: workflow_id, project_id: project_id} = insert(:simple_workflow)

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/projects/#{project_id}/workflows/#{workflow_id}")

      assert %{"error" => "Unauthorized"} == json_response(conn, 401)
    end
  end

  describe "POST /workflows/:project_id" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "inserts a workflow", %{conn: conn, project: project} do
      workflow =
        build(:simple_workflow, name: "work1", project_id: project.id)

      conn =
        post(
          conn,
          ~p"/api/projects/#{project.id}/workflows/",
          Jason.encode!(workflow)
        )

      assert %{"workflow" => response_workflow, "errors" => %{}} =
               json_response(conn, 201)

      assert %{
               edges: [edge],
               jobs: [job],
               triggers: [trigger]
             } =
               saved_workflow = get_saved_workflow(response_workflow["id"])

      assert encode_decode(response_workflow) == encode_decode(saved_workflow)

      assert Map.take(hd(workflow.edges), [:condition_type, :enabled]) ==
               Map.take(edge, [:condition_type, :enabled])

      assert Map.take(hd(workflow.jobs), [:name, :adaptor, :body]) ==
               Map.take(job, [:name, :adaptor, :body])

      assert Map.take(hd(workflow.triggers), [:type, :enabled]) ==
               Map.take(trigger, [:type, :enabled])

      assert Map.take(workflow, [:name, :project_id]) ==
               Map.take(saved_workflow, [:name, :project_id])
    end

    test "inserts a workflow with disconnected job", %{
      conn: conn,
      project: project
    } do
      workflow =
        build(:simple_workflow, name: "work1", project_id: project.id)
        |> then(fn %{jobs: jobs} = workflow ->
          %{workflow | jobs: [build(:job) | jobs]}
        end)

      conn =
        post(
          conn,
          ~p"/api/projects/#{project.id}/workflows/",
          Jason.encode!(workflow)
        )

      assert %{"workflow" => response_workflow, "errors" => %{}} =
               json_response(conn, 201)

      assert saved_workflow = get_saved_workflow(response_workflow["id"])

      assert response_workflow == encode_decode(saved_workflow)

      assert pluck_to_mapset(workflow.edges, [:condition_type, :enabled]) ==
               pluck_to_mapset(saved_workflow.edges, [:condition_type, :enabled])

      assert pluck_to_mapset(workflow.jobs, [:name, :adaptor, :body]) ==
               pluck_to_mapset(saved_workflow.jobs, [:name, :adaptor, :body])

      assert pluck_to_mapset(workflow.triggers, [:type, :enabled]) ==
               pluck_to_mapset(saved_workflow.triggers, [:type, :enabled])

      assert Map.take(workflow, [:name, :project_id]) ==
               Map.take(saved_workflow, [:name, :project_id])
    end

    test "creates UUIDs on insert based on user arbitrary ids", %{
      conn: conn,
      project: project
    } do
      workflow =
        build(:complex_workflow, project_id: project.id)
        |> then(fn %{
                     jobs: [job1, job2 | jobs],
                     edges: edges,
                     triggers: [trigger]
                   } = workflow ->
          old_job1_id = job1.id
          old_job2_id = job2.id
          job1 = Map.put(job1, :id, 11)
          job2 = Map.put(job2, :id, 12)
          old_trigger_id = trigger.id
          trigger = Map.put(trigger, :id, "trigger1")

          ids_map = %{
            old_job1_id => 11,
            old_job2_id => 12,
            old_trigger_id => "trigger1"
          }

          edges
          |> Enum.map(fn edge ->
            edge
            |> Map.update(:source_trigger_id, nil, &Map.get(ids_map, &1, &1))
            |> Map.update(:source_job_id, nil, &Map.get(ids_map, &1, &1))
            |> Map.update(:target_job_id, nil, &Map.get(ids_map, &1, &1))
          end)
          |> then(fn edges ->
            %{
              workflow
              | jobs: [job1, job2 | jobs],
                edges: edges,
                triggers: [trigger]
            }
          end)
        end)

      assert %{
               "workflow" => response_workflow,
               "errors" => %{}
             } =
               conn
               |> post(
                 ~p"/api/projects/#{project.id}/workflows",
                 Jason.encode!(workflow)
               )
               |> json_response(201)

      saved_workflow = get_saved_workflow(response_workflow["id"])

      assert encode_decode(response_workflow) |> remove_timestamps() ==
               encode_decode(saved_workflow) |> remove_timestamps()
    end

    test "returns 422 when an edge has invalid condition_type", %{
      conn: conn,
      project: project
    } do
      %{edges: [edge | _edges]} =
        workflow =
        build(:simple_workflow, name: "work1", project_id: project.id)
        |> then(fn %{edges: [edge | edges]} = workflow ->
          %{workflow | edges: [%{edge | condition_type: "on_failures"} | edges]}
        end)

      conn =
        post(
          conn,
          ~p"/api/projects/#{project.id}/workflows/",
          Jason.encode!(workflow)
        )

      assert json_response(conn, 422) == %{
               "id" => nil,
               "errors" => %{
                 "edges" => [
                   "Edge #{edge.id} has the errors: [condition_type: is invalid]"
                 ]
               }
             }
    end

    test "returns 422 when a job has invalid value", %{
      conn: conn,
      project: project
    } do
      %{jobs: [job1, job2 | _jobs]} =
        workflow =
        build(:complex_workflow, name: "work1", project_id: project.id)
        |> then(fn %{jobs: [job1, job2 | jobs]} = workflow ->
          %{
            workflow
            | jobs: [
                %{job1 | body: ["mistake as list"]},
                %{job2 | adaptor: ["mistake as list"]} | jobs
              ]
          }
        end)

      conn =
        post(
          conn,
          ~p"/api/projects/#{project.id}/workflows/",
          Jason.encode!(workflow)
        )

      assert %{
               "id" => nil,
               "errors" => %{
                 "jobs" => jobs_errors
               }
             } = json_response(conn, 422)

      assert Enum.sort(jobs_errors) ==
               Enum.sort([
                 "Job #{job1.id} has the errors: [body: is invalid]",
                 "Job #{job2.id} has the errors: [adaptor: is invalid]"
               ])
    end

    test "returns 422 when a trigger has invalid value", %{
      conn: conn,
      project: project
    } do
      %{triggers: [trigger]} =
        workflow =
        build(:complex_workflow, name: "work1", project_id: project.id)
        |> then(fn %{triggers: [trigger]} = workflow ->
          %{workflow | triggers: [%{trigger | enabled: "always"}]}
        end)

      conn =
        post(
          conn,
          ~p"/api/projects/#{project.id}/workflows/",
          Jason.encode!(workflow)
        )

      assert %{
               "id" => nil,
               "errors" => %{
                 "triggers" => [
                   "Trigger #{trigger.id} has the errors: [enabled: is invalid]"
                 ]
               }
             } == json_response(conn, 422)
    end

    test "returns 422 when workflow limit has been reached", %{
      conn: conn,
      project: project
    } do
      insert(:simple_workflow, name: "work1", project: project)

      workflow =
        build(:simple_workflow, name: "work2", project_id: project.id)

      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn
          %{type: :activate_workflow}, _context ->
            {:error, :too_many_workflows, %Message{text: "some limit error msg"}}
        end
      )

      conn =
        post(
          conn,
          ~p"/api/projects/#{project.id}/workflows/",
          Jason.encode!(workflow)
        )

      assert %{
               "id" => nil,
               "errors" => %{
                 "project_id" => ["some limit error msg"]
               }
             } = json_response(conn, 422)
    end

    test "returns 422 when there are too many active triggers", %{
      conn: conn,
      project: project
    } do
      workflow =
        build(:simple_workflow,
          name: "workflow",
          triggers: build_list(2, :trigger),
          project_id: project.id
        )

      conn =
        post(
          conn,
          ~p"/api/projects/#{project.id}/workflows/",
          Jason.encode!(workflow)
        )

      assert %{
               "id" => nil,
               "errors" => %{
                 "triggers" => [
                   "A workflow can have only one trigger enabled at a time."
                 ]
               }
             } = json_response(conn, 422)
    end

    test "returns 422 on project id mismatch", %{
      conn: conn,
      user: user,
      project: project
    } do
      other_project =
        insert(:project, project_users: [%{user: user, role: :owner}])

      workflow =
        build(:simple_workflow, name: "work1", project_id: project.id)

      conn =
        post(
          conn,
          ~p"/api/projects/#{other_project.id}/workflows",
          Jason.encode!(workflow)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "project_id" => [
                   "The project_id of the body does not match the one the path."
                 ]
               }
             }
    end

    test "returns 422 when graph has a cycle", %{
      conn: conn,
      project: project
    } do
      workflow =
        build(:complex_workflow, name: "work1", project_id: project.id)
        |> then(fn %{jobs: jobs, edges: edges} = workflow ->
          job0 = Enum.at(jobs, 0)
          job3 = Enum.at(jobs, 3)

          %{
            workflow
            | edges:
                edges ++
                  [build(:edge, source_job_id: job3.id, target_job_id: job0.id)]
          }
        end)

      conn =
        post(
          conn,
          ~p"/api/projects/#{project.id}/workflows",
          Jason.encode!(workflow)
        )

      job0 = Enum.at(workflow.jobs, 0)

      assert json_response(conn, 422) == %{
               "id" => nil,
               "errors" => %{
                 "edges" => ["Cycle detected on job #{job0.id}."]
               }
             }
    end

    test "returns 422 when there is a duplicated id", %{
      conn: conn,
      project: project
    } do
      %{id: edge_id} = insert(:edge)

      workflow =
        build(:simple_workflow,
          name: "workflow",
          project_id: project.id
        )
        |> then(fn %{edges: [edge]} = workflow ->
          %{workflow | edges: [Map.put(edge, :id, edge_id)]}
        end)

      conn =
        post(
          conn,
          ~p"/api/projects/#{project.id}/workflows/",
          Jason.encode!(workflow)
        )

      assert %{
               "id" => nil,
               "errors" => %{
                 "edges" => [
                   "Edge #{edge_id} has the errors: [id: This value should be unique.]"
                 ]
               }
             } == json_response(conn, 422)
    end

    test "returns 422 when edges misses a source trigger", %{
      conn: conn,
      project: project
    } do
      trigger =
        build(:trigger, type: :webhook, enabled: true)

      workflow =
        build(:workflow, name: "workflow 1", project_id: project.id)
        |> with_trigger(trigger)
        |> then(fn workflow ->
          job1 = build(:job)
          job2 = build(:job)

          %{
            workflow
            | jobs: [job1, job2],
              edges: [
                build(:edge, source_job_id: job1.id, target_job_id: job2.id)
              ]
          }
        end)

      conn =
        post(
          conn,
          ~p"/api/projects/#{project.id}/workflows",
          Jason.encode!(workflow)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "edges" => ["Missing edge with source_trigger_id."]
               }
             }
    end

    test "returns 422 when edges has multiple source triggers", %{
      conn: conn,
      project: project
    } do
      trigger =
        build(:trigger, type: :webhook, enabled: true)

      workflow =
        build(:workflow, name: "workflow 1", project_id: project.id)
        |> with_trigger(trigger)
        |> then(fn %{triggers: [trigger]} = workflow ->
          job1 = build(:job)
          job2 = build(:job)

          %{
            workflow
            | jobs: [job1, job2],
              edges: [
                build(:edge,
                  source_trigger_id: trigger.id,
                  target_job_id: job1.id
                ),
                build(:edge, source_job_id: job1.id, target_job_id: job2.id),
                build(:edge,
                  source_trigger_id: trigger.id,
                  target_job_id: job2.id
                )
              ]
          }
        end)

      conn =
        post(
          conn,
          ~p"/api/projects/#{project.id}/workflows",
          Jason.encode!(workflow)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "edges" => [
                   "There should be only one enabled edge with source_trigger_id."
                 ]
               }
             }
    end

    test "returns 422 when an edge source_job_id points to a trigger", %{
      conn: conn,
      project: project
    } do
      workflow =
        build(:simple_workflow, project_id: project.id)
        |> then(fn %{jobs: [job1], triggers: [trigger]} = workflow ->
          job2 = build(:job)

          %{
            workflow
            | jobs: [job1, job2],
              edges: [
                build(:edge,
                  source_trigger_id: trigger.id,
                  target_job_id: job1.id
                ),
                build(:edge, source_job_id: trigger.id, target_job_id: job2.id)
              ]
          }
        end)

      conn =
        post(
          conn,
          ~p"/api/projects/#{project.id}/workflows",
          Jason.encode!(workflow)
        )

      assert json_response(conn, 422) == %{
               "id" => nil,
               "errors" => %{
                 "edges" => [
                   "source_trigger_id must have a single target."
                 ]
               }
             }
    end

    test "returns 401 without a token", %{project: project} do
      build(:simple_workflow, name: "work1", project: project)

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/projects/#{project.id}/workflows/")

      assert %{"error" => "Unauthorized"} == json_response(conn, 401)
    end
  end

  describe "PATCH /workflows/:workflow_id" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "updates a workflow trigger", %{conn: conn, project: project} do
      %{edges: [edge1 | other_edges], triggers: [trigger]} =
        workflow =
        insert(:simple_workflow, name: "work1.0", project: project)
        |> Repo.reload()
        |> Repo.preload([:edges, :jobs, :triggers])

      patch =
        build(:trigger, type: :cron, cron_expression: "0 0 * * *", enabled: true)
        |> then(
          &%{
            name: "work1.1",
            edges: [%{edge1 | source_trigger_id: &1.id} | other_edges],
            triggers: [%{trigger | enabled: false}, &1]
          }
        )

      conn =
        patch(
          conn,
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert %{"workflow" => response_workflow, "errors" => %{}} =
               json_response(conn, 200)

      saved_workflow = get_saved_workflow(workflow)

      assert encode_decode(response_workflow) == encode_decode(saved_workflow)

      assert workflow
             |> Map.merge(patch)
             |> encode_decode()
             |> remove_timestamps() ==
               saved_workflow
               |> encode_decode()
               |> remove_timestamps()
    end

    test "adds some jobs to a workflow", %{conn: conn, project: project} do
      %{edges: edges, jobs: jobs} =
        workflow =
        insert(:simple_workflow, name: "work1.0", project: project)
        |> Repo.reload()
        |> Repo.preload([:edges, :jobs, :triggers])

      patch =
        build(:job)
        |> then(fn job ->
          %{
            name: "work1.1",
            edges:
              edges ++
                [
                  build(:edge,
                    source_job_id: List.last(jobs).id,
                    target_job_id: job.id,
                    condition_type: :on_job_success
                  )
                ],
            jobs: jobs ++ [job]
          }
        end)

      conn =
        patch(
          conn,
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert %{"workflow" => response_workflow, "errors" => %{}} =
               json_response(conn, 200)

      saved_workflow = get_saved_workflow(workflow)

      assert encode_decode(response_workflow) == encode_decode(saved_workflow)

      assert workflow
             |> Map.merge(patch)
             |> encode_decode()
             |> remove_timestamps() ==
               saved_workflow
               |> encode_decode()
               |> remove_timestamps()
    end

    test "Adds a disconnected/orphan job", %{conn: conn, project: project} do
      %{jobs: jobs} =
        workflow =
        insert(:simple_workflow, name: "work1.0", project: project)
        |> Repo.preload([:jobs])

      job = build(:job)

      patch =
        %{
          name: "work1.1",
          jobs: jobs ++ [job]
        }

      conn =
        patch(
          conn,
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert %{"workflow" => response_workflow, "errors" => %{}} =
               json_response(conn, 200)

      saved_workflow = get_saved_workflow(workflow)

      # assert both response_workflow and saved_workflow has the same jobs
      # regardless of order
      assert MapSet.new(
               response_workflow["jobs"],
               &Map.take(&1, ["id", "name", "adaptor", "body"])
             ) ==
               MapSet.new(
                 saved_workflow.jobs,
                 &(Map.take(&1, [:id, :name, :adaptor, :body])
                   |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end))
               )

      assert workflow
             |> Map.merge(patch)
             |> encode_decode()
             |> remove_timestamps() ==
               saved_workflow
               |> encode_decode()
               |> remove_timestamps()
    end

    test "returns 404 when the workflow doesn't exist", %{
      conn: conn,
      project: project
    } do
      unexisting_id = Ecto.UUID.generate()
      patch = %{name: "work1.1"}

      assert %{"id" => ^unexisting_id, "errors" => ["Not Found"]} =
               conn
               |> patch(
                 ~p"/api/projects/#{project.id}/workflows/#{unexisting_id}",
                 Jason.encode!(patch)
               )
               |> json_response(404)
    end

    test "returns 409 when the workflow is being edited on the UI" do
      %{conn: conn, user: user} =
        register_and_log_in_user(%{conn: Phoenix.ConnTest.build_conn()})

      project =
        insert(:project, project_users: [%{user: user}])

      workflow = workflow_fixture(name: "work1.0", project_id: project.id)

      refute Presence.has_any_presence?(workflow)

      {:ok, _view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}/legacy")

      patch = %{name: "work1.1"}

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> assign_bearer(user)
        |> patch(
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert json_response(conn, 409) == %{
               "id" => workflow.id,
               "errors" => %{
                 "workflow" => [
                   "Cannot save a workflow (work1.0) while it is being edited on the App UI"
                 ]
               }
             }

      assert Presence.has_any_presence?(workflow)
    end

    test "returns 422 for invalid triggers patch", %{
      conn: conn,
      project: project
    } do
      %{triggers: [trigger]} =
        workflow =
        insert(:simple_workflow, name: "work1.0", project: project)
        |> Repo.reload()
        |> Repo.preload([:edges, :jobs, :triggers])

      patch =
        %{
          name: "work1.1",
          triggers: [%{trigger | custom_path: ["invalid path in list"]}]
        }

      conn =
        patch(
          conn,
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "triggers" => [
                   "Trigger #{trigger.id} has the errors: [custom_path: is invalid]"
                 ]
               }
             }
    end

    test "returns 422 for invalid jobs patch", %{
      conn: conn,
      project: project
    } do
      %{jobs: [job | other_jobs]} =
        workflow =
        insert(:simple_workflow, name: "work1.0", project: project)
        |> Repo.reload()
        |> Repo.preload([:edges, :jobs, :triggers])

      patch =
        %{
          name: "work1.1",
          jobs: [%{job | body: ["invalid body in list"]} | other_jobs]
        }

      conn =
        patch(
          conn,
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "jobs" => ["Job #{job.id} has the errors: [body: is invalid]"]
               }
             }
    end

    test "returns 422 for invalid edges patch", %{
      conn: conn,
      project: project
    } do
      %{edges: [edge]} =
        workflow =
        insert(:simple_workflow, name: "work1.0", project: project)
        |> Repo.reload()
        |> Repo.preload([:edges, :jobs, :edges])

      patch =
        %{
          name: "work1.1",
          edges: [%{edge | condition_type: "on_faillllure"}]
        }

      conn =
        patch(
          conn,
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "edges" => [
                   "Edge #{edge.id} has the errors: [condition_type: is invalid]"
                 ]
               }
             }
    end

    test "returns 422 on project id mismatch", %{
      conn: conn,
      project: project
    } do
      workflow =
        insert(:simple_workflow, name: "work1", project: project)
        |> Repo.reload()
        |> Repo.preload([:edges, :jobs, :triggers])

      patch = %{project_id: Ecto.UUID.generate()}

      conn =
        patch(
          conn,
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "project_id" => [
                   "The project_id of the body does not match the one the path."
                 ]
               }
             }
    end

    test "returns 422 when trying to replace the triggers", %{
      conn: conn,
      project: project
    } do
      workflow =
        insert(:simple_workflow, name: "work1", project: project)
        |> Repo.reload()
        |> Repo.preload([:edges, :jobs, :triggers])

      patch =
        %{
          triggers: [
            build(:trigger,
              type: :cron,
              cron_expression: "0 0 * * *",
              enabled: true
            )
          ]
        }

      conn =
        patch(
          conn,
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "triggers" => [
                   "A trigger cannot be replaced, only edited or added."
                 ]
               }
             }
    end

    test "returns 422 when workflow limit has been reached", %{
      conn: conn,
      project: project
    } do
      insert(:simple_workflow, name: "work1", project: project)

      trigger = build(:trigger, enabled: false)

      workflow =
        insert(:simple_workflow, name: "work2", project: project)
        |> with_trigger(trigger)

      patch = %{triggers: [%{(workflow.triggers |> hd()) | enabled: true}]}

      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn
          %{type: :activate_workflow}, _context ->
            {:error, :too_many_workflows,
             %Message{text: "some limit error message"}}
        end
      )

      conn =
        patch(
          conn,
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert %{
               "id" => workflow.id,
               "errors" => %{
                 "project_id" => ["some limit error message"]
               }
             } == json_response(conn, 422)
    end

    test "returns 422 when there are too many enabled triggers", %{
      conn: conn,
      project: project
    } do
      workflow =
        insert(:simple_workflow, name: "work1", project: project)
        |> Repo.reload()
        |> Repo.preload([:edges, :jobs, :triggers])

      patch =
        %{
          triggers: [
            build(:trigger,
              type: :cron,
              cron_expression: "0 0 * * *",
              enabled: true
            )
            | workflow.triggers
          ]
        }

      conn =
        patch(
          conn,
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "triggers" => [
                   "A workflow can have only one trigger enabled at a time."
                 ]
               }
             }
    end

    test "returns 401 without a token", %{project: project} do
      workflow = insert(:simple_workflow, name: "work1", project: project)

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> patch(
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(%{name: "work-2"})
        )

      assert %{"error" => "Unauthorized"} == json_response(conn, 401)
    end
  end

  describe "PUT /workflows/:workflow_id" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "updates completely a workflow", %{conn: conn, project: project} do
      %{triggers: [trigger]} =
        workflow =
        insert(:simple_workflow, name: "work1.0", project: project)
        |> Repo.reload()
        |> Repo.preload([:edges, :jobs, :triggers])

      complete_update =
        build(:simple_workflow, name: "work1.1", project: project)
        |> then(fn %{
                     edges: [new_edge | other_new_edges],
                     jobs: [new_job1 | _other_jobs] = new_jobs,
                     triggers: [new_trigger]
                   } ->
          Map.merge(workflow, %{
            edges: [
              Map.merge(new_edge, %{
                source_trigger_id: new_trigger.id,
                target_job_id: new_job1.id,
                condition_expression: "state.age > 18",
                condition_label: "adult_age"
              })
              | other_new_edges
            ],
            jobs: new_jobs,
            triggers: [%{trigger | enabled: false}, new_trigger]
          })
        end)

      assert %{"workflow" => response_workflow, "errors" => %{}} =
               conn
               |> put(
                 ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
                 Jason.encode!(complete_update)
               )
               |> json_response(200)

      assert_response(response_workflow)

      saved_workflow =
        get_saved_workflow(response_workflow["id"])
        |> encode_decode()
        |> remove_timestamps()

      assert workflow
             |> Map.merge(complete_update)
             |> encode_decode()
             |> remove_timestamps() == saved_workflow
    end

    test "updates completely a workflow with disconnected job", %{
      conn: conn,
      project: project
    } do
      %{triggers: [trigger]} =
        workflow =
        insert(:simple_workflow, name: "work1.0", project: project)
        |> Repo.reload()
        |> Repo.preload([:edges, :jobs, :triggers])

      complete_update =
        build(:simple_workflow, name: "work1.1", project: project)
        |> then(fn %{
                     edges: [new_edge | other_new_edges],
                     jobs: [new_job1 | _other_jobs],
                     triggers: [new_trigger]
                   } ->
          Map.merge(workflow, %{
            edges: [
              %{
                new_edge
                | source_trigger_id: new_trigger.id,
                  target_job_id: new_job1.id
              }
              | other_new_edges
            ],
            jobs: [build(:job), new_job1 | workflow.jobs],
            triggers: [%{trigger | enabled: false}, new_trigger]
          })
        end)

      conn =
        put(
          conn,
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(complete_update)
        )

      assert %{"workflow" => response_workflow, "errors" => %{}} =
               json_response(conn, 200)

      previous_workflow_jobs_ids = Enum.map(workflow.jobs, & &1.id)

      saved_workflow = get_saved_workflow(workflow)

      assert Enum.filter(
               response_workflow["jobs"],
               &(&1["id"] not in previous_workflow_jobs_ids)
             )
             |> Enum.count() == 2

      assert Enum.filter(
               saved_workflow.jobs,
               &(&1.id not in previous_workflow_jobs_ids)
             )
             |> Enum.count() == 2
    end

    test "updates completely a workflow removing a job", %{
      conn: conn,
      project: project
    } do
      workflow =
        insert(:complex_workflow, name: "work1.0", project: project)
        |> Repo.reload()
        |> Repo.preload([:edges, :jobs, :triggers])

      complete_update =
        workflow
        |> then(fn %{
                     edges: edges,
                     jobs: jobs
                   } ->
          last_job = List.last(jobs)
          last_edge = List.last(edges)

          Map.merge(workflow, %{
            name: "work1.1",
            edges: List.delete(edges, last_edge),
            jobs: List.delete(jobs, last_job)
          })
        end)

      assert %{"workflow" => response_workflow, "errors" => %{}} =
               conn
               |> put(
                 ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
                 Jason.encode!(complete_update)
               )
               |> json_response(200)

      assert_response(response_workflow)

      saved_workflow = get_saved_workflow(workflow.id)

      refute MapSet.new(complete_update.jobs, & &1.id) ==
               MapSet.new(workflow.jobs, & &1.id)

      refute MapSet.new(complete_update.edges, & &1.id) ==
               MapSet.new(workflow.edges, & &1.id)

      assert MapSet.new(complete_update.jobs, & &1.id) ==
               MapSet.new(saved_workflow.jobs, & &1.id)

      assert MapSet.new(complete_update.edges, & &1.id) ==
               MapSet.new(saved_workflow.edges, & &1.id)
    end

    test "updates workflow ignoring workflow_id", %{
      conn: conn,
      project: project
    } do
      %{triggers: [trigger]} =
        workflow =
        insert(:simple_workflow, name: "work1.0", project: project)
        |> Repo.reload()
        |> Repo.preload([:edges, :jobs, :triggers])

      %{id: other_workflow_id} = insert(:simple_workflow)

      complete_update_external_ref =
        build(:simple_workflow, name: "work1.1", project: project)
        |> then(fn %{
                     edges: [new_edge | other_new_edges],
                     jobs: [new_job | other_jobs],
                     triggers: [new_trigger]
                   } ->
          Map.merge(workflow, %{
            edges: [
              Map.merge(new_edge, %{
                source_trigger_id: new_trigger.id,
                target_job_id: new_job.id,
                workflow_id: other_workflow_id
              })
              | other_new_edges
            ],
            jobs: [
              %{new_job | workflow_id: other_workflow_id}
              | other_jobs
            ],
            triggers: [
              %{trigger | enabled: false},
              %{new_trigger | workflow_id: other_workflow_id}
            ]
          })
        end)

      assert %{
               "workflow" => response_workflow,
               "errors" => %{}
             } =
               conn
               |> put(
                 ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
                 Jason.encode!(complete_update_external_ref)
               )
               |> json_response(200)

      assert_response(response_workflow)
    end

    test "returns 404 when the workflow doesn't exist", %{
      conn: conn,
      project: project
    } do
      unexisting_id = Ecto.UUID.generate()
      workflow = build(:simple_workflow, project_id: project.id)

      assert %{"id" => ^unexisting_id, "errors" => ["Not Found"]} =
               conn
               |> put(
                 ~p"/api/projects/#{project.id}/workflows/#{unexisting_id}",
                 Jason.encode!(Map.put(workflow, :id, unexisting_id))
               )
               |> json_response(404)
    end

    test "returns 409 when the workflow is being edited on the UI" do
      %{conn: conn, user: user} =
        register_and_log_in_user(%{conn: Phoenix.ConnTest.build_conn()})

      project =
        insert(:project, project_users: [%{user: user}])

      workflow =
        workflow_fixture(name: "work1.0", project_id: project.id)
        |> Repo.preload([:edges, :jobs, :triggers])

      refute Presence.has_any_presence?(workflow)

      {:ok, _view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}/legacy")

      workflow_update = %{workflow | name: "work1.1"}

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> assign_bearer(user)
        |> put(
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(workflow_update)
        )

      assert json_response(conn, 409) == %{
               "id" => workflow.id,
               "errors" => %{
                 "workflow" => [
                   "Cannot save a workflow (work1.0) while it is being edited on the App UI"
                 ]
               }
             }

      assert Presence.has_any_presence?(workflow)
    end

    test "returns 404 when the workflow id doesn't match the one on the path", %{
      conn: conn,
      project: project
    } do
      unexisting_id = Ecto.UUID.generate()
      workflow = build(:simple_workflow, project_id: project.id)

      assert %{
               "id" => ^unexisting_id,
               "errors" => %{
                 "id" => ["Workflow ID doesn't match with the one on the path."]
               }
             } =
               conn
               |> put(
                 ~p"/api/projects/#{project.id}/workflows/#{unexisting_id}",
                 Jason.encode!(workflow)
               )
               |> json_response(422)
    end

    test "returns 422 when one id belongs to another workflow", %{
      conn: conn,
      project: project
    } do
      %{triggers: [trigger]} =
        workflow =
        insert(:simple_workflow, name: "work1.0", project: project)
        |> Repo.reload()
        |> Repo.preload([:edges, :jobs, :triggers])

      %{jobs: [external_job | _jobs]} = insert(:simple_workflow)

      complete_update_external_id =
        build(:simple_workflow, name: "work1.1", project: project)
        |> then(fn %{
                     edges: [new_edge | other_new_edges],
                     jobs: [new_job | other_jobs],
                     triggers: [new_trigger]
                   } ->
          Map.merge(workflow, %{
            edges: [
              %{
                new_edge
                | source_trigger_id: new_trigger.id,
                  target_job_id: external_job.id
              }
              | other_new_edges
            ],
            jobs: [
              %{new_job | id: external_job.id} | other_jobs
            ],
            triggers: [
              %{trigger | enabled: false},
              new_trigger
            ]
          })
        end)

      conn =
        put(
          conn,
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(complete_update_external_id)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "jobs" => [
                   "Job #{external_job.id} has the errors: [id: This value should be unique.]"
                 ]
               }
             }
    end

    test "returns 422 when trying to replace the triggers", %{
      conn: conn,
      project: project
    } do
      workflow =
        insert(:simple_workflow, name: "work1.0", project: project)
        |> Repo.reload()
        |> Repo.preload([:edges, :jobs, :triggers])

      invalid_update =
        build(:simple_workflow, name: "work1.1", project: project)
        |> then(fn %{
                     edges: [new_edge | other_new_edges],
                     jobs: [new_job1 | _other_jobs] = new_jobs,
                     triggers: [new_trigger]
                   } ->
          Map.merge(workflow, %{
            edges: [
              %{
                new_edge
                | source_trigger_id: new_trigger.id,
                  target_job_id: new_job1.id
              }
              | other_new_edges
            ],
            jobs: new_jobs,
            triggers: [new_trigger]
          })
        end)

      conn =
        put(
          conn,
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(invalid_update)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "triggers" => [
                   "A trigger cannot be replaced, only edited or added."
                 ]
               }
             }
    end

    test "returns 401 without a token", %{project: project} do
      workflow = insert(:simple_workflow, name: "work1", project: project)

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> put(
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(%{workflow | name: "work2"})
        )

      assert %{"error" => "Unauthorized"} == json_response(conn, 401)
    end
  end

  defp encode_decode(item) do
    item
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp remove_timestamps([%{"edges" => _el} | _workflows] = list)
       when is_list(list) do
    Enum.map(list, &Map.drop(&1, ["inserted_at", "updated_at"]))
  end

  defp remove_timestamps(list) when is_list(list) do
    Enum.map(list, &Map.drop(&1, ["inserted_at", "updated_at"]))
  end

  defp remove_timestamps(workflow) do
    Map.merge(workflow, %{
      "inserted_at" => nil,
      "updated_at" => nil,
      "edges" => remove_timestamps(workflow["edges"]),
      "jobs" => remove_timestamps(workflow["jobs"]),
      "triggers" => remove_timestamps(workflow["triggers"])
    })
  end

  defp get_saved_workflow(%{id: workflow_id}),
    do: get_saved_workflow(workflow_id)

  defp get_saved_workflow(workflow_id),
    do: Workflows.get_workflow(workflow_id, include: [:edges, :jobs, :triggers])

  defp assert_response(response_workflow) do
    response_workflow = encode_decode(response_workflow)

    saved_workflow =
      response_workflow["id"] |> get_saved_workflow() |> encode_decode()

    assert MapSet.new(response_workflow["jobs"]) ==
             MapSet.new(saved_workflow["jobs"])

    assert MapSet.new(response_workflow["edges"]) ==
             MapSet.new(saved_workflow["edges"])

    assert MapSet.new(response_workflow["triggers"]) ==
             MapSet.new(saved_workflow["triggers"])
  end

  defp pluck_to_mapset(map, keys) do
    map
    |> Enum.into(MapSet.new(), fn e ->
      Map.take(e, keys)
    end)
  end
end
