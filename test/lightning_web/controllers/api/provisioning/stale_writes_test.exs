defmodule LightningWeb.API.ProvisioningStaleWritesTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProvisioningHelpers
  import LightningWeb.API.ProblemHelpers
  import Ecto.Query
  import Lightning.Factories

  alias Lightning.Workflows.Workflow

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "a stale write" do
    setup [:assign_bearer_for_api]

    setup %{user: user} do
      %{
        project:
          insert(:project, project_users: [%{user_id: user.id, role: :owner}])
      }
    end

    test "a workflow another request changes mid-import answers 409 concurrent_edit and keeps that request's change",
         %{conn: conn, project: project} do
      %{body: body, workflow_id: workflow_id, trigger_id: trigger_id} =
        valid_payload(project.id)

      conn |> post(~p"/api/provision", body) |> json_response(201)
      before = Lightning.Repo.get!(Workflow, workflow_id)

      # Enabling the trigger asks the usage limiter, which runs after the
      # document is read and before it is written. The workflows are read by
      # parallel preload tasks, so no query in the request's own process falls
      # between the read and the write.
      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn %{type: :activate_workflow}, _context ->
          from(w in Workflow, where: w.id == ^workflow_id)
          |> Lightning.Repo.update_all(inc: [lock_version: 1])

          :ok
        end
      )

      body =
        put_in(
          body,
          ["workflows", Access.at(0), "triggers", Access.at(0), "enabled"],
          true
        )

      conn
      |> post(~p"/api/provision", body)
      |> assert_problem(409, :concurrent_edit, [])

      assert Lightning.Repo.get!(Workflow, workflow_id).lock_version ==
               before.lock_version + 1

      refute Lightning.Repo.get!(Lightning.Workflows.Trigger, trigger_id).enabled
    end
  end
end
