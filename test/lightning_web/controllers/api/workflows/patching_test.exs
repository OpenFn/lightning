defmodule LightningWeb.API.Workflows.PatchingTest do
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

      assert %{"workflow" => response_workflow} =
               json_response(conn, 200)

      saved_workflow = get_saved_workflow(workflow)

      assert_response(response_workflow)

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

      assert %{"workflow" => response_workflow} =
               json_response(conn, 200)

      saved_workflow = get_saved_workflow(workflow)

      assert_response(response_workflow)

      merged =
        workflow |> Map.merge(patch) |> encode_decode() |> remove_timestamps()

      saved = saved_workflow |> encode_decode() |> remove_timestamps()

      assert MapSet.new(merged["jobs"]) == MapSet.new(saved["jobs"])
      assert MapSet.new(merged["edges"]) == MapSet.new(saved["edges"])
      assert MapSet.new(merged["triggers"]) == MapSet.new(saved["triggers"])

      assert Map.drop(merged, ["jobs", "edges", "triggers"]) ==
               Map.drop(saved, ["jobs", "edges", "triggers"])
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

      assert %{"workflow" => response_workflow} =
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
          triggers: [%{trigger | comment: ["invalid comment in list"]}]
        }

      conn =
        patch(
          conn,
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert_problem(conn, 422, :invalid, [
        %{
          "pointer" => "#/triggers/0/comment",
          "code" => "type",
          "detail" => "is invalid"
        }
      ])
    end

    test "accepts a triggers patch that echoes an existing custom_path", %{
      conn: conn,
      project: project
    } do
      # The CLI round-trips whole documents, so a trigger that already has a
      # custom_path sends the same value back on every deploy. That must not
      # 422.
      %{triggers: [trigger]} =
        workflow =
        insert(:simple_workflow, name: "work1.0", project: project)
        |> Repo.reload()
        |> Repo.preload([:edges, :jobs, :triggers])

      trigger =
        trigger
        |> Ecto.Changeset.change(custom_path: "partner-feed")
        |> Repo.update!()

      patch = %{
        name: "work1.1",
        triggers: [%{trigger | comment: "untouched routing"}]
      }

      conn =
        patch(
          conn,
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      json_response(conn, 200)
      assert Repo.reload!(trigger).custom_path == "partner-feed"
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

      assert_problem(conn, 422, :invalid, [
        %{
          "pointer" => "#/jobs/0/body",
          "code" => "type",
          "detail" => "is invalid"
        }
      ])
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

      assert_problem(conn, 422, :invalid, [
        %{
          "pointer" => "#/edges/0/condition_type",
          "code" => "not_allowed",
          "detail" => "is invalid"
        }
      ])
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

      assert_problem(conn, 422, :invalid, [
        %{
          "pointer" => "#/project_id",
          "code" => "mismatch",
          "detail" => "does not match the id in the path"
        }
      ])
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

      assert_problem(conn, 422, :invalid, [
        %{
          "pointer" => "#/triggers",
          "code" => "trigger_removed",
          "detail" => "a trigger cannot be removed, only edited or added"
        },
        %{
          "pointer" => "#/edges",
          "code" => "missing_trigger_edge",
          "detail" => "needs an enabled edge from a trigger"
        }
      ])
    end

    test "returns 402 when an update enables a trigger over the workflow limit",
         %{conn: conn, project: project} do
      workflow =
        insert(:simple_workflow, name: "work2", project: project)
        |> Repo.preload([:edges, :jobs, :triggers])

      [trigger] = workflow.triggers
      trigger |> Ecto.Changeset.change(enabled: false) |> Repo.update!()

      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn %{type: :activate_workflow}, _context ->
          {:error, :too_many_workflows,
           %Message{text: "some limit error message"}}
        end
      )

      patch = %{triggers: [%{id: trigger.id, enabled: true}]}

      conn
      |> patch(
        ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
        Jason.encode!(patch)
      )
      |> assert_problem(402, :exceeds_limit, [])
    end

    test "an invalid update that enables a trigger over the workflow limit answers 422, not 402",
         %{conn: conn, project: project} do
      workflow =
        insert(:simple_workflow, name: "work2", project: project)
        |> Repo.preload([:edges, :jobs, :triggers])

      [trigger] = workflow.triggers
      trigger |> Ecto.Changeset.change(enabled: false) |> Repo.update!()

      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn %{type: :activate_workflow}, _context ->
          {:error, :too_many_workflows, %Message{text: "upgrade"}}
        end
      )

      patch = %{name: "", triggers: [%{id: trigger.id, enabled: true}]}

      conn
      |> patch(
        ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
        Jason.encode!(patch)
      )
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/name",
          "code" => "required",
          "detail" => "can't be blank"
        }
      ])
    end

    test "an update that leaves an enabled trigger enabled isn't held to the workflow limit",
         %{conn: conn, project: project} do
      workflow =
        insert(:simple_workflow, name: "work2", project: project)
        |> Repo.preload([:edges, :jobs, :triggers])

      [trigger] = workflow.triggers
      assert trigger.enabled

      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn %{type: :activate_workflow}, _context ->
          {:error, :exceeds_limit, %Message{text: "some limit error message"}}
        end
      )

      patch = %{name: "renamed", triggers: [%{id: trigger.id, enabled: true}]}

      assert %{"workflow" => %{"name" => "renamed"}} =
               conn
               |> patch(
                 ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
                 Jason.encode!(patch)
               )
               |> json_response(200)
    end

    test "answers 404 for a workflow that is missing or deleted, whatever the body holds",
         %{conn: conn, project: project} do
      deleted =
        insert(:simple_workflow,
          project: project,
          deleted_at: DateTime.utc_now()
        )

      for {id, body} <- [
            {Ecto.UUID.generate(), %{name: "renamed"}},
            {deleted.id, %{name: "renamed"}},
            {deleted.id, %{name: ""}}
          ] do
        conn
        |> patch(
          ~p"/api/projects/#{project.id}/workflows/#{id}",
          Jason.encode!(body)
        )
        |> assert_problem(404, :not_found, [])
      end
    end
  end
end
