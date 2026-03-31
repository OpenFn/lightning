defmodule LightningWeb.API.WorkflowsControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  test "without a token", %{conn: conn} do
    conn = get(conn, ~p"/api/workflows")

    assert %{"error" => "Unauthorized"} == json_response(conn, 401)
  end

  describe "with invalid token" do
    test "gets a 401", %{conn: conn} do
      token = "InvalidToken"

      conn =
        conn
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")

      conn = get(conn, ~p"/api/workflows")
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
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

    test "nested route returns 401 for project user cannot access", %{
      conn: conn
    } do
      other_project = insert(:project)

      conn = get(conn, ~p"/api/projects/#{other_project.id}/workflows")

      assert json_response(conn, 401)
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
  end
end
