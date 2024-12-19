defmodule LightningWeb.API.WorkflowsControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

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

      assert %{"id" => workflow_id, "error" => nil} = json_response(conn, 200)

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
            {:error, :too_many_workflows, %{text: "any"}}
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
               "error" => "Your plan has reached the limit of active workflows."
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

      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn
          %{type: :activate_workflow}, _context ->
            {:error, :too_many_workflows, %{text: "any"}}
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
               "error" =>
                 "A workflow can have only one trigger enabled at a time."
             } = json_response(conn, 422)
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
        |> then(&%{name: "work1.1",
          edges: [%{edge1 | source_trigger_id: &1.id} | other_edges],
          triggers: [%{trigger | enabled: false}, &1]})

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
            edges: edges ++ [build(:edge, source_job_id: List.last(jobs).id, condition_type: :on_job_success)],
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
               "error" =>
                 "The triggers cannot be replaced, only edited or added."
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
            {:error, :too_many_workflows, %{text: "any"}}
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
               "error" => "Your plan has reached the limit of active workflows."
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
               "error" =>
                 "A workflow can have only one trigger enabled at a time."
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
               "error" =>
                 "The triggers cannot be replaced, only edited or added."
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
