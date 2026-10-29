defmodule LightningWeb.API.Workflows.ReadingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import Lightning.Factories
  import LightningWeb.ApiReadHelpers
  import LightningWeb.ApiWorkflowsHelpers

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn}
  end

  describe "listing workflows" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "answers the whole workflow, without its lifecycle state, on either route",
         %{conn: conn, project: project} do
      workflow =
        insert(:simple_workflow,
          name: "exact-check",
          project: project,
          state: :live
        )

      for path <- [
            ~p"/api/workflows",
            ~p"/api/projects/#{project.id}/workflows"
          ] do
        assert conn |> get(path) |> json_response(200) == %{
                 "workflows" => [encode_decode(workflow)]
               }
      end
    end

    test "lists the workflows of the projects I belong to, and no others", %{
      conn: conn,
      project: project
    } do
      workflow1 = insert(:workflow, project: project, name: "Workflow A")
      insert(:trigger, workflow: workflow1)
      insert(:job, workflow: workflow1)

      workflow2 = insert(:workflow, project: project, name: "Workflow B")
      insert(:trigger, workflow: workflow2)

      other_workflow = insert(:workflow, project: insert(:project))
      insert(:trigger, workflow: other_workflow)

      response = conn |> get(~p"/api/workflows") |> json_response(200)

      assert length(response["workflows"]) == 2

      workflow_ids = Enum.map(response["workflows"], & &1["id"])
      assert workflow1.id in workflow_ids
      assert workflow2.id in workflow_ids
      refute other_workflow.id in workflow_ids
    end

    test "narrows to one project by the project_id query parameter or by the nested route",
         %{conn: conn, user: user} do
      project1 =
        insert(:project, project_users: [%{user: user, role: :owner}])

      project2 =
        insert(:project, project_users: [%{user: user, role: :owner}])

      workflow1 = insert(:workflow, project: project1, name: "P1 Workflow")
      insert(:trigger, workflow: workflow1)

      workflow2 = insert(:workflow, project: project2, name: "P2 Workflow")
      insert(:trigger, workflow: workflow2)

      for path <- [
            ~p"/api/workflows?project_id=#{project1.id}",
            ~p"/api/projects/#{project1.id}/workflows"
          ] do
        assert [%{"id" => id}] =
                 conn
                 |> get(path)
                 |> json_response(200)
                 |> Map.fetch!("workflows")

        assert id == workflow1.id
      end
    end
  end

  describe "showing a workflow" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "answers the whole workflow, without its lifecycle state, on either route",
         %{conn: conn, project: project} do
      workflow = insert(:simple_workflow, project: project, state: :live)

      for path <- [
            ~p"/api/workflows/#{workflow.id}",
            ~p"/api/workflows/#{workflow.id}?#{%{project_id: Ecto.UUID.generate()}}",
            ~p"/api/projects/#{project.id}/workflows/#{workflow.id}"
          ] do
        assert conn |> get(path) |> json_response(200) == %{
                 "workflow" => encode_decode(workflow)
               }
      end
    end

    test "answers a member 404 for a deleted workflow, on either route, and for one of theirs outside the path's project",
         %{conn: member, user: user, project: project} do
      deleted =
        insert(:simple_workflow,
          project: project,
          deleted_at: DateTime.utc_now()
        )

      other_project =
        insert(:project, project_users: [%{user: user, role: :owner}])

      mine = insert(:simple_workflow, project: project)

      for path <- [
            ~p"/api/workflows/#{deleted.id}",
            ~p"/api/projects/#{project.id}/workflows/#{deleted.id}",
            ~p"/api/projects/#{other_project.id}/workflows/#{mine.id}"
          ] do
        member |> get(path) |> assert_problem(404, :not_found, [])
      end
    end

    test "has no edit route", %{conn: conn, project: project} do
      workflow = insert(:simple_workflow, project: project)

      conn
      |> get(~p"/api/projects/#{project.id}/workflows/#{workflow.id}/edit")
      |> assert_problem(404, :not_found, [])
    end
  end

  describe "who may reach it" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "a caller without permission gets the same 403 whether or not the workflow exists, and a permitted one 404 or 400",
         %{conn: member, project: project} do
      for {caller, path, status, code, entries} <-
            who_may_read(
              member,
              project,
              "workflows",
              &insert(:simple_workflow, project: &1)
            ) do
        caller |> get(path) |> assert_problem(status, code, entries)
      end
    end
  end
end
