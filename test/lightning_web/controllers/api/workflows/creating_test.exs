defmodule LightningWeb.API.Workflows.CreatingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import Lightning.Factories
  import LightningWeb.ApiWorkflowsHelpers

  alias Lightning.Extensions.Message

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn}
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

      assert %{"workflow" => %{"id" => id}} = body = json_response(conn, 201)

      assert %{
               edges: [edge],
               jobs: [job],
               triggers: [trigger]
             } =
               saved_workflow = get_saved_workflow(id)

      assert body == %{"workflow" => encode_decode(saved_workflow)}

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

      assert %{"workflow" => response_workflow} =
               json_response(conn, 201)

      assert saved_workflow = get_saved_workflow(response_workflow["id"])

      assert_response(response_workflow)

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
               "workflow" => response_workflow
             } =
               conn
               |> post(
                 ~p"/api/projects/#{project.id}/workflows",
                 Jason.encode!(workflow)
               )
               |> json_response(201)

      saved_workflow = get_saved_workflow(response_workflow["id"])

      merged = encode_decode(response_workflow) |> remove_timestamps()
      saved = encode_decode(saved_workflow) |> remove_timestamps()

      assert MapSet.new(merged["jobs"]) == MapSet.new(saved["jobs"])
      assert MapSet.new(merged["edges"]) == MapSet.new(saved["edges"])
      assert MapSet.new(merged["triggers"]) == MapSet.new(saved["triggers"])

      assert Map.drop(merged, ["jobs", "edges", "triggers"]) ==
               Map.drop(saved, ["jobs", "edges", "triggers"])
    end

    test "returns 422 when an edge has invalid condition_type", %{
      conn: conn,
      project: project
    } do
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

      assert_problem(conn, 422, :invalid, [
        %{
          "pointer" => "#/edges/0/condition_type",
          "code" => "not_allowed",
          "detail" => "is invalid"
        }
      ])
    end

    test "returns 422 when a job has invalid value", %{
      conn: conn,
      project: project
    } do
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

      assert_problem(conn, 422, :invalid, [
        %{
          "pointer" => "#/jobs/0/body",
          "code" => "type",
          "detail" => "is invalid"
        },
        %{
          "pointer" => "#/jobs/1/adaptor",
          "code" => "type",
          "detail" => "is invalid"
        }
      ])
    end

    test "returns 422 when a job references another project's credential", %{
      conn: conn,
      project: project
    } do
      other_project = insert(:project)
      project_credential = insert(:project_credential, project: other_project)

      workflow =
        build(:simple_workflow, name: "work1", project_id: project.id)
        |> then(fn %{jobs: [job]} = workflow ->
          %{
            workflow
            | jobs: [%{job | project_credential_id: project_credential.id}]
          }
        end)

      conn =
        post(
          conn,
          ~p"/api/projects/#{project.id}/workflows/",
          Jason.encode!(workflow)
        )

      assert_problem(conn, 422, :invalid, [
        %{
          "pointer" => "#/jobs/0/project_credential_id",
          "code" => "credential_not_allowed",
          "detail" =>
            "credential doesn't exist or isn't available in this project"
        }
      ])
    end

    test "returns 422 when a trigger has invalid value", %{
      conn: conn,
      project: project
    } do
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

      assert_problem(conn, 422, :invalid, [
        %{
          "pointer" => "#/triggers/0/enabled",
          "code" => "type",
          "detail" => "is invalid"
        }
      ])
    end

    test "returns 402 when workflow limit has been reached", %{
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

      assert_problem(conn, 402, :exceeds_limit, [])
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

      assert_problem(conn, 422, :invalid, [
        %{
          "pointer" => "#/project_id",
          "code" => "mismatch",
          "detail" => "does not match the id in the path"
        }
      ])
    end

    test "returns 422 with a taken entry when there is a duplicated id", %{
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

      assert_problem(conn, 422, :invalid, [
        %{
          "pointer" => "#/edges/0/id",
          "code" => "taken",
          "detail" => "has already been taken"
        }
      ])
    end

    test "reports a cycle at the edge that closes it", %{
      conn: conn,
      project: project
    } do
      body =
        graph_body(project.id, [{"t", "a"}, {"a", "b"}, {"b", "c"}, {"c", "a"}])

      conn
      |> post(~p"/api/projects/#{project.id}/workflows", Jason.encode!(body))
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/edges/3/target_job_id",
          "code" => "cycle",
          "detail" => "is part of a cycle"
        }
      ])
    end

    test "reports an id that is missing or names no job at the place it was sent",
         %{conn: conn, project: project} do
      missing_job_id =
        project.id
        |> graph_body([{"t", "a"}, {"a", "b"}])
        |> update_in(["jobs"], fn [a, b, c] -> [a, b, Map.delete(c, "id")] end)

      for {body, entry} <- [
            {missing_job_id,
             %{
               "pointer" => "#/jobs/2/id",
               "code" => "required",
               "detail" => "can't be blank"
             }},
            {graph_body(project.id, [{"t", "a"}, {"a", "nowhere"}]),
             %{
               "pointer" => "#/edges/1/target_job_id",
               "code" => "format",
               "detail" => "is not a valid UUID"
             }},
            {graph_body(project.id, [{"t", "a"}, {"a", Ecto.UUID.generate()}]),
             %{
               "pointer" => "#/edges/1/target_job_id",
               "code" => "not_found",
               "detail" => "job doesn't exist, or is not in the same workflow"
             }}
          ] do
        conn
        |> post(~p"/api/projects/#{project.id}/workflows", Jason.encode!(body))
        |> assert_problem(422, :invalid, [entry])
      end
    end

    test "a body that is invalid and over the plan limit answers 422, not 402",
         %{conn: conn, project: project} do
      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn %{type: :activate_workflow}, _context ->
          {:error, :exceeds_limit, %Message{text: "upgrade"}}
        end
      )

      cyclic = graph_body(project.id, [{"t", "a"}, {"a", "b"}, {"b", "a"}])

      conn
      |> post(~p"/api/projects/#{project.id}/workflows", Jason.encode!(cyclic))
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/edges/2/target_job_id",
          "code" => "cycle",
          "detail" => "is part of a cycle"
        }
      ])
    end
  end
end
