defmodule LightningWeb.API.UnexpectedErrorsTest do
  use LightningWeb.ConnCase, async: true

  import ExUnit.CaptureLog
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiProjectsHelpers, only: [put_project: 3]

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "a workflow write whose snapshot can't be saved" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "answers 500 internal, logs it, and leaves the workflow as it was", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:simple_workflow, name: "before", project: project)

      # The snapshot of a save carries the lock_version the save produces, so a
      # snapshot already holding it makes the save's own snapshot collide.
      insert(:snapshot,
        workflow: workflow,
        lock_version: workflow.lock_version + 1
      )

      log =
        capture_log(fn ->
          conn
          |> put_req_header("content-type", "application/json")
          |> patch(
            ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
            Jason.encode!(%{name: "after"})
          )
          |> assert_problem(500, :internal, [])
        end)

      assert log =~ "An API action could not save a workflow snapshot"
      assert Repo.reload!(workflow).name == "before"
    end
  end

  describe "a project change whose audit events can't be written" do
    setup %{conn: conn} do
      {conn, account} = with_service_account(conn, ["projects:write"])

      # An account with no uuid has no actor id to record, so its audit events
      # are refused.
      Mox.stub(Lightning.MockConfig, :service_account, fn ->
        %{account | uuid: nil}
      end)

      %{conn: conn}
    end

    test "answers 500 internal, logs it, and leaves the project as it was", %{
      conn: conn
    } do
      owner = insert(:user)

      project =
        insert(:project,
          name: "before",
          project_users: [%{user: owner, role: :owner}]
        )

      log =
        capture_log(fn ->
          conn
          |> put_project(project.id, %{
            "name" => "after",
            "members" => [%{"email" => owner.email, "role" => "owner"}]
          })
          |> assert_problem(500, :internal, [])
        end)

      assert log =~
               "An API action could not write the audit events of a project change"

      assert Repo.reload!(project).name == "before"
    end
  end
end
