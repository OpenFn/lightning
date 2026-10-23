defmodule LightningWeb.API.Workflows.RefusalsTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import Lightning.Factories
  import Lightning.RaceHelpers
  import Lightning.WorkflowsFixtures
  import LightningWeb.ApiWorkflowsHelpers

  alias Lightning.Workflows.Presence

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn}
  end

  describe "who may reach it" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    @tag role: :viewer
    test "viewer cannot create a workflow", %{conn: conn, project: project} do
      workflow =
        build(:simple_workflow,
          name: "viewer-created-workflow",
          project_id: project.id
        )

      conn =
        post(
          conn,
          ~p"/api/projects/#{project.id}/workflows/",
          Jason.encode!(workflow)
        )

      assert_problem(conn, 403, :forbidden, [])

      refute Lightning.Repo.get_by(Lightning.Workflows.Workflow,
               name: "viewer-created-workflow"
             )
    end

    @tag role: :viewer
    test "viewer hears 404 for a workflow the project hasn't got, and 403 for one it has, and changes nothing",
         %{conn: conn, project: project} do
      workflow =
        insert(:simple_workflow, name: "original-name", project: project)

      body = Jason.encode!(%{name: "hacked-by-viewer"})

      conn
      |> patch(
        ~p"/api/projects/#{project.id}/workflows/#{Ecto.UUID.generate()}",
        body
      )
      |> assert_problem(404, :not_found, [])

      conn
      |> patch(~p"/api/projects/#{project.id}/workflows/#{workflow.id}", body)
      |> assert_problem(403, :forbidden, [])

      assert Repo.reload(workflow).name == "original-name"
    end

    test "admin, editor and owner can create a workflow", %{conn: conn} do
      for role <- [:admin, :editor, :owner] do
        user = insert(:user)
        project = insert(:project, project_users: [%{user: user, role: role}])

        workflow =
          build(:simple_workflow,
            name: "#{role}-created-workflow",
            project_id: project.id
          )

        resp_conn =
          conn
          |> assign_bearer(user)
          |> post(
            ~p"/api/projects/#{project.id}/workflows/",
            Jason.encode!(workflow)
          )

        assert %{"workflow" => %{"id" => id}} =
                 json_response(resp_conn, 201),
               "expected #{role} to be allowed to create a workflow"

        assert Lightning.Repo.get(Lightning.Workflows.Workflow, id)
      end
    end

    test "admin, editor and owner can update a workflow", %{conn: conn} do
      for role <- [:admin, :editor, :owner] do
        user = insert(:user)
        project = insert(:project, project_users: [%{user: user, role: role}])

        workflow =
          insert(:simple_workflow, name: "#{role}-original", project: project)
          |> Repo.reload()

        resp_conn =
          conn
          |> assign_bearer(user)
          |> patch(
            ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
            Jason.encode!(%{name: "#{role}-updated"})
          )

        assert %{"workflow" => %{}} =
                 json_response(resp_conn, 200),
               "expected #{role} to be allowed to update a workflow"

        assert Repo.reload(workflow).name == "#{role}-updated"
      end
    end
  end

  describe "refusals and what they leave alone" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "a caller with no standing gets 404, whether or not the workflow is open in the editor",
         %{conn: conn} do
      editor = insert(:user)
      project = insert(:project, project_users: [%{user: editor}])
      workflow = insert(:simple_workflow, project: project)
      path = ~p"/api/projects/#{project.id}/workflows/#{workflow.id}"

      conn
      |> patch(path, Jason.encode!(%{"name" => "renamed"}))
      |> assert_problem(404, :not_found, [])

      Presence.track_user_presence(editor, workflow, self())
      assert Presence.has_any_presence?(workflow)

      conn
      |> patch(path, Jason.encode!(%{"name" => "renamed"}))
      |> assert_problem(404, :not_found, [])
    end

    test "a member short of the project's MFA requirement hears 404 for a workflow the project hasn't got, and 403 for one it has",
         %{conn: conn, project: project} do
      workflow = insert(:simple_workflow, project: project)
      Repo.update!(Ecto.Changeset.change(project, requires_mfa: true))

      conn
      |> get(~p"/api/projects/#{project.id}/workflows/#{Ecto.UUID.generate()}")
      |> assert_problem(404, :not_found, [])

      conn
      |> get(~p"/api/projects/#{project.id}/workflows/#{workflow.id}")
      |> assert_problem(403, :forbidden, [])
    end

    test "never quotes a value from the request, on any route", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:simple_workflow, project: project)
      sentinel = plant_sentinel(%{"v" => "x"})["v"]

      planted =
        project.id
        |> graph_body([{"t", "a"}, {"a", "b"}, {"b", "a"}])
        |> Map.delete("project_id")
        |> plant_sentinel()

      for path <- [
            ~p"/api/workflows/#{sentinel}",
            ~p"/api/workflows?project_id=#{sentinel}",
            ~p"/api/projects/#{sentinel}/workflows",
            ~p"/api/projects/#{sentinel}/workflows/#{workflow.id}",
            ~p"/api/projects/#{project.id}/workflows/#{sentinel}"
          ] do
        conn
        |> get(path)
        |> refute_sentinel()
        |> assert_problem(404, :not_found, [])
      end

      conn
      |> post(~p"/api/projects/#{project.id}/workflows", Jason.encode!(planted))
      |> refute_sentinel()
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/edges",
          "code" => "single_target",
          "detail" => "a trigger must have a single target"
        },
        %{
          "pointer" => "#/edges/0/condition_type",
          "code" => "not_allowed",
          "detail" => "is invalid"
        },
        %{
          "pointer" => "#/edges/1/condition_type",
          "code" => "not_allowed",
          "detail" => "is invalid"
        },
        %{
          "pointer" => "#/edges/1/target_job_id",
          "code" => "cycle",
          "detail" => "target_job_id must be different from source_job_id"
        },
        %{
          "pointer" => "#/edges/2/condition_type",
          "code" => "not_allowed",
          "detail" => "is invalid"
        },
        %{
          "pointer" => "#/edges/2/target_job_id",
          "code" => "cycle",
          "detail" => "target_job_id must be different from source_job_id"
        },
        %{
          "pointer" => "#/triggers/0/type",
          "code" => "not_allowed",
          "detail" => "is invalid"
        },
        %{
          "pointer" => "#/triggers/0/enabled",
          "code" => "type",
          "detail" => "is invalid"
        }
      ])

      for request <- [&patch/3, &put/3] do
        conn
        |> request.(
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(Map.put(planted, "id", sentinel))
        )
        |> refute_sentinel()
        |> assert_problem(422, :invalid, [
          %{
            "pointer" => "#/id",
            "code" => "mismatch",
            "detail" => "does not match the id in the path"
          },
          %{
            "pointer" => "#/triggers",
            "code" => "trigger_removed",
            "detail" => "a trigger cannot be removed, only edited or added"
          },
          %{
            "pointer" => "#/edges",
            "code" => "single_target",
            "detail" => "a trigger must have a single target"
          },
          %{
            "pointer" => "#/edges/0/condition_type",
            "code" => "not_allowed",
            "detail" => "is invalid"
          },
          %{
            "pointer" => "#/edges/0/source_trigger_id",
            "code" => "format",
            "detail" => "is not a valid UUID"
          },
          %{
            "pointer" => "#/edges/0/target_job_id",
            "code" => "format",
            "detail" => "is not a valid UUID"
          },
          %{
            "pointer" => "#/edges/1/condition_type",
            "code" => "not_allowed",
            "detail" => "is invalid"
          },
          %{
            "pointer" => "#/edges/1/source_job_id",
            "code" => "format",
            "detail" => "is not a valid UUID"
          },
          %{
            "pointer" => "#/edges/1/target_job_id",
            "code" => "format",
            "detail" => "is not a valid UUID"
          },
          %{
            "pointer" => "#/edges/1/target_job_id",
            "code" => "cycle",
            "detail" => "target_job_id must be different from source_job_id"
          },
          %{
            "pointer" => "#/edges/2/condition_type",
            "code" => "not_allowed",
            "detail" => "is invalid"
          },
          %{
            "pointer" => "#/edges/2/source_job_id",
            "code" => "format",
            "detail" => "is not a valid UUID"
          },
          %{
            "pointer" => "#/edges/2/target_job_id",
            "code" => "format",
            "detail" => "is not a valid UUID"
          },
          %{
            "pointer" => "#/edges/2/target_job_id",
            "code" => "cycle",
            "detail" => "target_job_id must be different from source_job_id"
          },
          %{
            "pointer" => "#/triggers/0/type",
            "code" => "not_allowed",
            "detail" => "is invalid"
          },
          %{
            "pointer" => "#/triggers/0/enabled",
            "code" => "type",
            "detail" => "is invalid"
          },
          %{
            "pointer" => "#/triggers/0/id",
            "code" => "format",
            "detail" => "is not a valid UUID"
          },
          %{
            "pointer" => "#/jobs/0/id",
            "code" => "format",
            "detail" => "is not a valid UUID"
          },
          %{
            "pointer" => "#/jobs/1/id",
            "code" => "format",
            "detail" => "is not a valid UUID"
          },
          %{
            "pointer" => "#/jobs/1/id",
            "code" => "duplicate",
            "detail" => "names the same id as #/jobs/0"
          },
          %{
            "pointer" => "#/jobs/2/id",
            "code" => "format",
            "detail" => "is not a valid UUID"
          },
          %{
            "pointer" => "#/jobs/2/id",
            "code" => "duplicate",
            "detail" => "names the same id as #/jobs/0"
          }
        ])

        conn
        |> request.(
          ~p"/api/projects/#{project.id}/workflows/#{sentinel}",
          Jason.encode!(planted)
        )
        |> refute_sentinel()
        |> assert_problem(404, :not_found, [])
      end
    end
  end

  describe "PATCH of a workflow that is changing elsewhere" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "returns 409 when the workflow is being edited on the UI" do
      %{conn: conn, user: user} =
        register_and_log_in_user(%{conn: Phoenix.ConnTest.build_conn()})

      project =
        insert(:project, project_users: [%{user: user}])

      workflow = workflow_fixture(name: "work1.0", project_id: project.id)

      refute Presence.has_any_presence?(workflow)

      # Simulate a user editing the workflow in the collaborative editor by
      # tracking their presence on the workflow.
      Presence.track_user_presence(user, workflow, self())

      patch = %{name: "work1.1"}

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> assign_bearer(user)
        |> patch(
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(patch)
        )

      assert_problem(conn, 409, :being_edited, [])

      assert Presence.has_any_presence?(workflow)
    end

    test "a workflow another request saves mid-update answers 409 concurrent_edit",
         %{conn: conn, project: project} do
      workflow = insert(:simple_workflow, name: "work1.0", project: project)

      bump_workflow_lock_mid_save(workflow.id)

      conn
      |> patch(
        ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
        Jason.encode!(%{name: "work1.1"})
      )
      |> assert_problem(409, :concurrent_edit, [])

      assert %{name: "work1.0", lock_version: 1} = Repo.reload(workflow)
    end

    test "a workflow open in the editor answers 409 before its body is read",
         %{conn: conn, project: project, user: user} do
      workflow = insert(:simple_workflow, project: project)
      Presence.track_user_presence(user, workflow, self())

      conn
      |> patch(
        ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
        "[1]"
      )
      |> assert_problem(409, :being_edited, [])
    end
  end

  describe "PUT of a workflow that is changing elsewhere" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "returns 409 when the workflow is being edited on the UI" do
      %{conn: conn, user: user} =
        register_and_log_in_user(%{conn: Phoenix.ConnTest.build_conn()})

      project =
        insert(:project, project_users: [%{user: user}])

      workflow =
        workflow_fixture(name: "work1.0", project_id: project.id)
        |> Repo.preload([:edges, :jobs, :triggers])

      refute Presence.has_any_presence?(workflow)

      # Simulate a user editing the workflow in the collaborative editor by
      # tracking their presence on the workflow.
      Presence.track_user_presence(user, workflow, self())

      workflow_update = %{workflow | name: "work1.1"}

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> assign_bearer(user)
        |> put(
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
          Jason.encode!(workflow_update)
        )

      assert_problem(conn, 409, :being_edited, [])

      assert Presence.has_any_presence?(workflow)
    end
  end
end
