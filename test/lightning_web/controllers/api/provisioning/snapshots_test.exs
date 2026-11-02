defmodule LightningWeb.API.ProvisioningSnapshotsTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProvisioningHelpers
  import LightningWeb.API.ProblemHelpers
  import Lightning.Factories

  alias Lightning.Workflows.Snapshot

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "exporting only the snapshots asked for" do
    setup [:assign_bearer_for_api]

    test "returns a project only with the specified snapshots", %{
      conn: conn,
      user: user
    } do
      %{id: project_id, name: project_name} =
        project =
        insert(:project,
          project_users: [%{user_id: user.id}]
        )

      workflow_1 =
        insert(:simple_workflow,
          project: project,
          name: "workflow 1"
        )

      {:ok, snapshot_1} = Snapshot.create(workflow_1)

      {:ok, updated_workflow_1} =
        workflow_1
        |> Ecto.Changeset.change(%{name: "updated-workflow-name"})
        |> Lightning.Repo.update()

      workflow_2 =
        insert(:simple_workflow,
          project: project,
          name: "workflow 2"
        )

      {:ok, snapshot_2} = Snapshot.create(workflow_2)

      conn =
        get(conn, ~p"/api/provision/#{project_id}", snapshots: [snapshot_1.id])

      response = json_response(conn, 200)

      assert %{
               "id" => ^project_id,
               "name" => ^project_name,
               "workflows" => [workflow_resp]
             } = response["data"]

      # Only the first workflow is returned because its snapshot was specified
      assert workflow_resp["id"] == workflow_1.id
      # The name of the workflow is the original name, not the updated name
      assert workflow_resp["name"] == workflow_1.name
      assert updated_workflow_1.name != workflow_1.name

      # Now we specify both snapshots
      conn =
        get(conn, ~p"/api/provision/#{project_id}",
          snapshots: [snapshot_1.id, snapshot_2.id]
        )

      response = json_response(conn, 200)

      assert %{"workflows" => workflows} = response["data"]
      assert Enum.count(workflows) == 2
    end

    test "does not return snapshots from another project", %{
      conn: conn,
      user: user
    } do
      %{id: project_id} =
        insert(:project, project_users: [%{user_id: user.id}])

      # A snapshot in a different project the user has no access to.
      foreign_workflow = insert(:simple_workflow, project: insert(:project))
      {:ok, foreign_snapshot} = Snapshot.create(foreign_workflow)

      conn =
        get(conn, ~p"/api/provision/#{project_id}",
          snapshots: [foreign_snapshot.id]
        )

      # The foreign snapshot's workflow is not disclosed.
      assert %{"workflows" => []} = json_response(conn, 200)["data"]
    end

    test "returns valid project yaml for snapshots provided" do
      project = insert(:project)
      repo_connection = insert(:project_repo_connection, project: project)

      workflow_1 =
        insert(:simple_workflow,
          project: project,
          name: "workflow 1"
        )

      {:ok, snapshot_1} = Snapshot.create(workflow_1)

      {:ok, updated_workflow_1} =
        workflow_1
        |> Ecto.Changeset.change(%{name: "updated-workflow-name"})
        |> Lightning.Repo.update()

      workflow_2 =
        insert(:simple_workflow,
          project: project,
          name: "workflow 2"
        )

      {:ok, snapshot_2} = Snapshot.create(workflow_2)

      conn =
        put_bearer(build_conn(), repo_connection.access_token)

      response =
        get(
          conn,
          ~p"/api/provision/yaml?#{%{id: project.id, snapshots: [snapshot_1.id]}}"
        )
        |> response(200)

      assert response =~ workflow_1.name
      refute response =~ updated_workflow_1.name
      refute response =~ workflow_2.name

      response =
        get(
          conn,
          ~p"/api/provision/yaml?#{%{id: project.id, snapshots: [snapshot_1.id, snapshot_2.id]}}"
        )
        |> response(200)

      assert response =~ workflow_1.name
      refute response =~ updated_workflow_1.name
      assert response =~ workflow_2.name
    end

    test "does not include another project's snapshots in the yaml" do
      project = insert(:project)
      repo_connection = insert(:project_repo_connection, project: project)

      foreign_workflow =
        insert(:simple_workflow,
          project: insert(:project),
          name: "foreign-workflow-name"
        )

      {:ok, foreign_snapshot} = Snapshot.create(foreign_workflow)

      conn =
        put_bearer(build_conn(), repo_connection.access_token)

      response =
        get(
          conn,
          ~p"/api/provision/yaml?#{%{id: project.id, snapshots: [foreign_snapshot.id]}}"
        )
        |> response(200)

      refute response =~ "foreign-workflow-name"
    end

    test "answers 400 invalid_parameter for snapshots that aren't a list of UUIDs, on both routes",
         %{conn: conn, user: user} do
      project = insert(:project, project_users: [%{user_id: user.id}])

      for path <- [
            ~p"/api/provision/#{project.id}",
            ~p"/api/provision/yaml?id=#{project.id}"
          ],
          snapshots <- ["true", ["not-a-uuid"]] do
        conn
        |> get(path, snapshots: snapshots)
        |> assert_problem(400, :invalid_parameter, [
          %{
            "parameter" => "snapshots",
            "code" => "type",
            "detail" => "is invalid"
          }
        ])
      end
    end
  end
end
