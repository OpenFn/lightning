defmodule LightningWeb.API.Workflows.PuttingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import Lightning.Factories
  import LightningWeb.ApiWorkflowsHelpers

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn}
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

      assert %{"workflow" => response_workflow} =
               conn
               |> put(
                 ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
                 Jason.encode!(complete_update)
               )
               |> json_response(200)

      assert_response(response_workflow)

      saved =
        get_saved_workflow(response_workflow["id"])
        |> encode_decode()
        |> remove_timestamps()

      merged =
        workflow
        |> Map.merge(complete_update)
        |> encode_decode()
        |> remove_timestamps()

      assert MapSet.new(merged["jobs"]) == MapSet.new(saved["jobs"])
      assert MapSet.new(merged["edges"]) == MapSet.new(saved["edges"])
      assert MapSet.new(merged["triggers"]) == MapSet.new(saved["triggers"])

      assert Map.drop(merged, ["jobs", "edges", "triggers"]) ==
               Map.drop(saved, ["jobs", "edges", "triggers"])
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

      assert %{"workflow" => response_workflow} =
               json_response(conn, 200)

      previous_workflow_jobs_ids = Enum.map(workflow.jobs, & &1.id)

      saved_workflow = get_saved_workflow(workflow)

      assert Enum.count(
               response_workflow["jobs"],
               &(&1["id"] not in previous_workflow_jobs_ids)
             ) == 2

      assert Enum.count(
               saved_workflow.jobs,
               &(&1.id not in previous_workflow_jobs_ids)
             ) == 2
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

      assert %{"workflow" => response_workflow} =
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
               "workflow" => response_workflow
             } =
               conn
               |> put(
                 ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
                 Jason.encode!(complete_update_external_ref)
               )
               |> json_response(200)

      assert_response(response_workflow)

      for {schema, children} <- [
            {Lightning.Workflows.Job, complete_update_external_ref.jobs},
            {Lightning.Workflows.Edge, complete_update_external_ref.edges},
            {Lightning.Workflows.Trigger, complete_update_external_ref.triggers}
          ],
          %{workflow_id: ^other_workflow_id, id: id} <- children do
        assert Repo.get!(schema, id).workflow_id == workflow.id
      end
    end

    test "returns 422 when the body's id doesn't match the one on the path", %{
      conn: conn,
      project: project
    } do
      workflow =
        insert(:simple_workflow, project: project)
        |> Repo.preload([:edges, :jobs, :triggers])

      conn
      |> put(
        ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
        Jason.encode!(%{workflow | id: Ecto.UUID.generate()})
      )
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/id",
          "code" => "mismatch",
          "detail" => "does not match the id in the path"
        }
      ])
    end

    test "returns 409 when one id belongs to another workflow", %{
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

      assert_problem(conn, 409, :taken, [
        %{
          "pointer" => "#/jobs/0/id",
          "code" => "taken",
          "detail" => "has already been taken"
        }
      ])
    end

    test "answers 404 for a workflow that is missing or deleted, whatever id the body gives",
         %{conn: conn, project: project} do
      deleted =
        insert(:simple_workflow,
          project: project,
          deleted_at: DateTime.utc_now()
        )

      missing_id = Ecto.UUID.generate()
      document = build(:simple_workflow, project_id: project.id)

      for {id, body} <- [
            {missing_id, document},
            {missing_id, Map.put(document, :id, missing_id)},
            {deleted.id, Map.put(document, :id, deleted.id)}
          ] do
        conn
        |> put(
          ~p"/api/projects/#{project.id}/workflows/#{id}",
          Jason.encode!(body)
        )
        |> assert_problem(404, :not_found, [])
      end
    end

    test "a body that isn't a JSON object answers 400", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:simple_workflow, project: project)

      conn
      |> put(~p"/api/projects/#{project.id}/workflows/#{workflow.id}", "[1]")
      |> assert_problem(400, :malformed, [])
    end
  end
end
