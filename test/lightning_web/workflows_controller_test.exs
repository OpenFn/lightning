defmodule LightningWeb.API.WorkflowsControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  alias Lightning.Extensions.Message
  alias Lightning.Workflows.Workflow

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn}
  end

  describe "GET /workflows" do
    test "returns a list of workflows", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      workflow1 = insert(:simple_workflow, name: "workf-A", project: project)
      workflow2 = insert(:simple_workflow, name: "workf-B", project: project)
      _workflow = insert(:simple_workflow)

      conn =
        conn
        |> assign_bearer(user)
        |> get(~p"/api/projects/#{project.id}/workflows/")

      assert json_response(conn, 200) == %{
               "error" => nil,
               "workflows" => [
                 encode_decode(workflow1),
                 encode_decode(workflow2)
               ]
             }
    end

    test "returns 401 without a token", %{conn: conn} do
      %{id: workflow_id, project_id: project_id} = insert(:simple_workflow)

      conn = get(conn, ~p"/api/projects/#{project_id}/workflows/#{workflow_id}")

      assert %{"error" => "Unauthorized"} == json_response(conn, 401)
    end

    test "returns 401 when a token is invalid", %{conn: conn} do
      %{id: workflow_id, project_id: project_id} =
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
        conn
        |> assign_bearer(token)
        |> get(~p"/api/projects/#{project_id}/workflows/#{workflow_id}")

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end

    test "returns 401 on a project the user don't have access to", %{conn: conn} do
      user = insert(:user)

      %{id: workflow_id, project_id: project_id} = insert(:simple_workflow)

      conn =
        conn
        |> assign_bearer(user)
        |> get(~p"/api/projects/#{project_id}/workflows/#{workflow_id}")

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "GET /workflows/:id" do
    test "returns a workflow", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      %{project_id: project_id} =
        workflow = insert(:simple_workflow, project: project)

      conn =
        conn
        |> assign_bearer(user)
        |> get(~p"/api/projects/#{project_id}/workflows/#{workflow.id}")

      assert json_response(conn, 200) == %{
               "error" => nil,
               "workflow" => encode_decode(workflow)
             }
    end

    test "returns 401 without a token", %{conn: conn} do
      %{id: workflow_id, project_id: project_id} = insert(:simple_workflow)

      conn = get(conn, ~p"/api/projects/#{project_id}/workflows/#{workflow_id}")

      assert %{"error" => "Unauthorized"} == json_response(conn, 401)
    end
  end

  describe "POST /workflows/:project_id" do
    test "inserts a workflow", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      workflow =
        build(:simple_workflow, name: "work1", project_id: project.id)

      conn =
        conn
        |> assign_bearer(user)
        |> post(
          ~p"/api/projects/#{project.id}/workflows/",
          Jason.encode!(workflow)
        )

      assert %{"id" => workflow_id, "error" => nil} = json_response(conn, 201)

      saved_workflow =
        Repo.get(Workflow, workflow_id)
        |> Repo.preload([:edges, :jobs, :triggers])
        |> encode_decode()
        |> remove_timestamps()

      assert workflow
             |> Map.put(:id, workflow_id)
             |> encode_decode()
             |> remove_timestamps() == saved_workflow
    end

    test "returns 422 when workflow limit has been reached", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

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
        conn
        |> assign_bearer(user)
        |> post(
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

    test "returns 422 when there are too many active triggers", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      workflow =
        build(:simple_workflow,
          name: "workflow",
          triggers: build_list(2, :trigger),
          project_id: project.id
        )

      conn =
        conn
        |> assign_bearer(user)
        |> post(
          ~p"/api/projects/#{project.id}/workflows/",
          Jason.encode!(workflow)
        )

      assert %{
               "id" => nil,
               "errors" => %{
                 "trigger_id" => [
                   "A workflow can have only one trigger enabled at a time."
                 ]
               }
             } = json_response(conn, 422)
    end

    test "returns 422 on project id mismatch", %{conn: conn} do
      user = insert(:user)

      project1 =
        insert(:project, project_users: [%{user: user}])

      project2 =
        insert(:project, project_users: [%{user: user}])

      workflow =
        build(:simple_workflow, name: "work1", project_id: project1.id)

      conn =
        conn
        |> assign_bearer(user)
        |> post(
          ~p"/api/projects/#{project2.id}/workflows",
          Jason.encode!(workflow)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "project_id" => [
                   "The project_id of the body does not match one one the path."
                 ]
               }
             }
    end

    test "returns 422 when graph has a cycle", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

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
        conn
        |> assign_bearer(user)
        |> post(
          ~p"/api/projects/#{project.id}/workflows",
          Jason.encode!(workflow)
        )

      job0 = Enum.at(workflow.jobs, 0)

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "edges" => ["Cycle detected on job #{job0.id}."]
               }
             }
    end

    test "returns 422 when trigger or job id is not a UUID", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      trigger =
        build(:trigger, type: :webhook, enabled: true)

      job =
        build(:job,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      trigger_foo = Map.put(trigger, :id, "foo")

      workflow1 =
        build(:workflow, name: "workflow 1", project_id: project.id)
        |> with_trigger(trigger_foo)
        |> with_job(job)
        |> with_edge({trigger, job}, [])

      job_bar = Map.put(job, :id, "bar")

      workflow2 =
        build(:workflow, name: "workflow 2", project_id: project.id)
        |> with_trigger(trigger)
        |> with_job(job_bar)
        |> with_edge({trigger, job}, [])

      conn = assign_bearer(conn, user)

      assert conn
             |> post(
               ~p"/api/projects/#{project.id}/workflows",
               Jason.encode!(workflow1)
             )
             |> json_response(422) == %{
               "id" => workflow1.id,
               "errors" => %{
                 "workflow" => ["Id foo should be a UUID."]
               }
             }

      assert conn
             |> post(
               ~p"/api/projects/#{project.id}/workflows",
               Jason.encode!(workflow2)
             )
             |> json_response(422) == %{
               "id" => workflow2.id,
               "errors" => %{
                 "workflow" => ["Id bar should be a UUID."]
               }
             }
    end

    test "returns 422 when trigger or job doesn't have an id", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      trigger =
        build(:trigger, type: :webhook, enabled: true)

      job =
        build(:job,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      workflow1 =
        build(:workflow, name: "workflow 1", project_id: project.id)
        |> with_job(job)
        |> with_edge({trigger, job}, [])
        |> then(&with_trigger(&1, Map.put(trigger, :id, nil)))

      workflow2 =
        build(:workflow, name: "workflow 2", project_id: project.id)
        |> with_trigger(trigger)
        |> with_edge({trigger, job}, [])
        |> then(&with_job(&1, Map.put(job, :id, nil)))

      conn = assign_bearer(conn, user)

      assert conn
             |> post(
               ~p"/api/projects/#{project.id}/workflows",
               Jason.encode!(workflow1)
             )
             |> json_response(422) == %{
               "id" => workflow1.id,
               "errors" => %{
                 "workflow" => [
                   "All jobs and triggers should have an id (UUID)."
                 ]
               }
             }

      assert conn
             |> post(
               ~p"/api/projects/#{project.id}/workflows",
               Jason.encode!(workflow2)
             )
             |> json_response(422) == %{
               "id" => workflow2.id,
               "errors" => %{
                 "workflow" => [
                   "All jobs and triggers should have an id (UUID)."
                 ]
               }
             }
    end

    test "returns 422 when there is a duplicated id", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

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
        conn
        |> assign_bearer(user)
        |> post(
          ~p"/api/projects/#{project.id}/workflows/",
          Jason.encode!(workflow)
        )

      assert %{
               "id" => nil,
               "errors" => %{
                 "workflow" => [
                   "These ids [#{inspect(edge_id)}] should be unique for all workflows."
                 ]
               }
             } == json_response(conn, 422)
    end

    test "returns 422 when edges misses a source trigger", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

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
        conn
        |> assign_bearer(user)
        |> post(
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

    test "returns 422 when edges has multiple source triggers", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

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
                build(:edge, source_job_id: trigger.id, target_job_id: job2.id)
              ]
          }
        end)

      conn =
        conn
        |> assign_bearer(user)
        |> post(
          ~p"/api/projects/#{project.id}/workflows",
          Jason.encode!(workflow)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "edges" => ["Has multiple targets for trigger #{trigger.id}."]
               }
             }
    end

    test "returns 401 without a token", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      build(:simple_workflow, name: "work1", project: project)

      conn = post(conn, ~p"/api/projects/#{project.id}/workflows/")

      assert %{"error" => "Unauthorized"} == json_response(conn, 401)
    end
  end

  describe "PATCH /workflows/:workflow_id" do
    test "updates a workflow trigger", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

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
        conn
        |> assign_bearer(user)
        |> patch(
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert %{"id" => workflow_id, "error" => nil} = json_response(conn, 200)
      assert Ecto.UUID.dump(workflow_id)

      saved_workflow =
        Repo.get(Workflow, workflow_id)
        |> Repo.preload([:edges, :jobs, :triggers])
        |> encode_decode()
        |> remove_timestamps()

      assert workflow
             |> Map.merge(patch)
             |> encode_decode()
             |> remove_timestamps() == saved_workflow
    end

    test "adds some jobs to a workflow", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

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
        conn
        |> assign_bearer(user)
        |> patch(
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert %{"id" => workflow_id, "error" => nil} = json_response(conn, 200)
      assert Ecto.UUID.dump(workflow_id)

      saved_workflow =
        Repo.get(Workflow, workflow_id)
        |> Repo.preload([:edges, :jobs, :triggers])
        |> encode_decode()
        |> remove_timestamps()

      assert workflow
             |> Map.merge(patch)
             |> encode_decode()
             |> remove_timestamps() == saved_workflow
    end

    test "returns 422 for dangling job", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      %{edges: edges, jobs: jobs} =
        workflow =
        insert(:simple_workflow, name: "work1.0", project: project)
        |> Repo.reload()
        |> Repo.preload([:edges, :jobs, :triggers])

      job = build(:job)

      patch =
        %{
          name: "work1.1",
          edges:
            edges ++
              [
                build(:edge,
                  source_job_id: List.last(jobs).id,
                  condition_type: :on_job_success
                )
              ],
          jobs: jobs ++ [job]
        }

      conn =
        conn
        |> assign_bearer(user)
        |> patch(
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "jobs" => [
                   "The jobs [\"#{job.id}\"] should be present both in the jobs and on an edge."
                 ]
               }
             }
    end

    test "returns 422 for invalid triggers patch", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

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
        conn
        |> assign_bearer(user)
        |> patch(
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "triggers" => [
                   "Trigger #{trigger.id} has the errors: [custom_path is invalid]"
                 ]
               }
             }
    end

    test "returns 422 for invalid jobs patch", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

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
        conn
        |> assign_bearer(user)
        |> patch(
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "jobs" => ["Job #{job.id} has the errors: [body is invalid]"]
               }
             }
    end

    test "returns 422 for invalid edges patch", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

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
        conn
        |> assign_bearer(user)
        |> patch(
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "edges" => [
                   "Edge #{edge.id} has the errors: [condition_type is invalid]"
                 ]
               }
             }
    end

    test "returns 422 on project id mismatch", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      workflow =
        insert(:simple_workflow, name: "work1", project: project)
        |> Repo.reload()
        |> Repo.preload([:edges, :jobs, :triggers])

      patch = %{project_id: Ecto.UUID.generate()}

      conn =
        conn
        |> assign_bearer(user)
        |> patch(
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "project_id" => [
                   "The project_id of the body does not match one one the path."
                 ]
               }
             }
    end

    test "returns 422 when trying to replace the triggers", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

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
        conn
        |> assign_bearer(user)
        |> patch(
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "trigger_id" => [
                   "Cannot be replaced, only edited or added."
                 ]
               }
             }
    end

    test "returns 422 when workflow limit has been reached", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

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
        conn
        |> assign_bearer(user)
        |> patch(
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

    test "returns 422 when there are too many enabled triggers", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

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
        conn
        |> assign_bearer(user)
        |> patch(
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "trigger_id" => [
                   "A workflow can have only one trigger enabled at a time."
                 ]
               }
             }
    end

    test "returns 401 without a token", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      workflow = insert(:simple_workflow, name: "work1", project: project)

      conn =
        patch(conn, ~p"/api/projects/#{project.id}/workflows/#{workflow.id}", %{
          name: "work-2"
        })

      assert %{"error" => "Unauthorized"} == json_response(conn, 401)
    end
  end

  describe "PUT /workflows/:workflow_id" do
    test "updates completely a workflow", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

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
              %{
                new_edge
                | source_trigger_id: new_trigger.id,
                  target_job_id: new_job1.id
              }
              | other_new_edges
            ],
            jobs: new_jobs,
            triggers: [%{trigger | enabled: false}, new_trigger]
          })
        end)

      conn =
        conn
        |> assign_bearer(user)
        |> put(
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(complete_update)
        )

      assert json_response(conn, 200) == %{"id" => workflow.id, "error" => nil}

      saved_workflow =
        Repo.get(Workflow, workflow.id)
        |> Repo.preload([:edges, :jobs, :triggers])
        |> encode_decode()
        |> remove_timestamps()

      assert workflow
             |> Map.merge(complete_update)
             |> encode_decode()
             |> remove_timestamps() == saved_workflow
    end

    test "returns 422 on reference to another workflow", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

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

      conn =
        conn
        |> assign_bearer(user)
        |> put(
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(complete_update_external_ref)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "workflow" => [
                   "Edges, jobs and triggers cannot reference another workflow!"
                 ]
               }
             }
    end

    test "returns 422 when one id belongs to another workflow", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

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
        conn
        |> assign_bearer(user)
        |> put(
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(complete_update_external_id)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "workflow" => [
                   "These ids [#{inspect(external_job.id)}] should be unique for all workflows."
                 ]
               }
             }
    end

    test "returns 422 when trying to replace the triggers", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

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
        conn
        |> assign_bearer(user)
        |> put(
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(invalid_update)
        )

      assert json_response(conn, 422) == %{
               "id" => workflow.id,
               "errors" => %{
                 "trigger_id" => [
                   "Cannot be replaced, only edited or added."
                 ]
               }
             }
    end

    test "returns 401 without a token", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      workflow = insert(:simple_workflow, name: "work1", project: project)

      conn =
        patch(conn, ~p"/api/projects/#{project.id}/workflows/#{workflow.id}", %{
          name: "work-2"
        })

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
end
