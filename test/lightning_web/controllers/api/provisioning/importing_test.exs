defmodule LightningWeb.API.ProvisioningImportingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProvisioningHelpers
  import LightningWeb.API.ProblemHelpers
  import Ecto.Query
  import Lightning.Factories

  alias Lightning.Workflows.Workflow

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "importing a document" do
    setup [:assign_bearer_for_api]

    test "fails with 402 when repo_connection is limited by github_sync", %{
      conn: conn
    } do
      %{id: project_id} = project = insert(:project)

      repo_connection =
        insert(:project_repo_connection, project: project)

      %{body: body} = valid_payload(project.id)

      conn =
        put_bearer(conn, repo_connection.access_token)

      error_text = "Upgrade to use Github Sync"

      Lightning.Extensions.MockUsageLimiter
      |> Mox.expect(:limit_action, fn %{type: :github_sync},
                                      %{project_id: ^project_id} ->
        {:error, :disabled, %Lightning.Extensions.Message{text: error_text}}
      end)

      conn = post(conn, ~p"/api/provision", body)
      assert_problem(conn, 402, :exceeds_limit, [])
      refute conn.resp_body =~ error_text
    end

    test "an owner replaces a project's name and jobs by posting a changed document",
         %{
           conn: conn,
           user: user
         } do
      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      %{
        project_id: project_id,
        body: body,
        second_job_id: second_job_id
      } = valid_payload(project.id)

      conn = post(conn, ~p"/api/provision", body)
      response = json_response(conn, 201)

      assert %{
               "id" => ^project_id,
               "name" => "test-project",
               "workflows" => [_]
             } = response["data"]

      # - - -
      third_job_id = Ecto.UUID.generate()

      body =
        body
        |> Map.put("name", "test-project-renamed")
        |> add_job_to_document(%{
          "id" => third_job_id,
          "name" => "third-job",
          "adaptor" => "@openfn/language-common@latest",
          "body" => "console.log('hello world');"
        })

      conn = post(conn, ~p"/api/provision", body)
      response = json_response(conn, 201)

      assert %{
               "id" => ^project_id,
               "name" => "test-project-renamed",
               "workflows" => workflows
             } = response["data"]

      workflow_job_ids =
        workflows |> Enum.at(0) |> Map.get("jobs") |> Enum.into([], & &1["id"])

      assert third_job_id in workflow_job_ids

      body = body |> remove_job_from_document(second_job_id)

      conn = post(conn, ~p"/api/provision", body)
      response = json_response(conn, 201)

      assert %{
               "id" => ^project_id,
               "name" => "test-project-renamed",
               "workflows" => workflows
             } = response["data"]

      workflow_job_ids =
        workflows |> Enum.at(0) |> Map.get("jobs") |> Enum.into([], & &1["id"])

      refute second_job_id in workflow_job_ids
      assert third_job_id in workflow_job_ids

      assert workflows |> Enum.at(0) |> Map.get("edges") == [],
             "The edge associated with the deleted job should be removed"
    end

    test "records workflow version with 'cli' source when workflow is created via provisioner",
         %{conn: conn, user: user} do
      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      %{body: body, workflow_id: workflow_id} = valid_payload(project.id)

      conn = post(conn, ~p"/api/provision", body)
      assert json_response(conn, 201)

      workflow = Lightning.Repo.get!(Workflow, workflow_id)
      version_history = Lightning.WorkflowVersions.history_for(workflow)

      assert length(version_history) == 1
      assert [version] = version_history
      assert String.starts_with?(version, "cli:")
    end

    test "records new workflow version when workflow is updated via provisioner",
         %{conn: conn, user: user} do
      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      # First provision - creates workflow
      %{body: body, workflow_id: workflow_id} = valid_payload(project.id)

      conn = post(conn, ~p"/api/provision", body)
      assert json_response(conn, 201)

      workflow = Lightning.Repo.get!(Workflow, workflow_id)
      initial_history = Lightning.WorkflowVersions.history_for(workflow)
      assert length(initial_history) == 1
      assert [initial_version] = initial_history
      assert String.starts_with?(initial_version, "cli:")

      # Update workflow by changing job body
      updated_body =
        body
        |> Map.update!("workflows", fn workflows ->
          Enum.at(workflows, 0)
          |> Map.update!("jobs", fn jobs ->
            Enum.map(jobs, fn job ->
              Map.put(job, "body", "console.log('updated');")
            end)
          end)
          |> then(fn workflow ->
            List.replace_at(workflows, 0, workflow)
          end)
        end)

      conn = post(conn, ~p"/api/provision", updated_body)
      assert json_response(conn, 201)

      workflow = Lightning.Repo.get!(Workflow, workflow_id)
      updated_history = Lightning.WorkflowVersions.history_for(workflow)

      # we nolonger squash the first version
      assert length(updated_history) == 2
      assert [^initial_version, latest_version] = updated_history
      assert String.starts_with?(latest_version, "cli:")

      # Verify the hash changed after the update
      refute initial_version == latest_version
    end

    test "does not create duplicate version when provisioning same workflow content",
         %{conn: conn, user: user} do
      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      # First provision - creates workflow
      %{body: body, workflow_id: workflow_id} = valid_payload(project.id)

      conn = post(conn, ~p"/api/provision", body)
      assert json_response(conn, 201)

      workflow = Lightning.Repo.get!(Workflow, workflow_id)
      initial_history = Lightning.WorkflowVersions.history_for(workflow)
      assert length(initial_history) == 1

      # Provision again with the exact same content
      conn = post(conn, ~p"/api/provision", body)
      assert json_response(conn, 201)

      workflow = Lightning.Repo.get!(Workflow, workflow_id)
      duplicate_history = Lightning.WorkflowVersions.history_for(workflow)

      # Should still have only 1 version since content didn't change
      assert length(duplicate_history) == 1
      assert duplicate_history == initial_history
    end

    test "handles provisioning with no workflow changes gracefully",
         %{conn: conn, user: user} do
      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      # Create a project with a workflow that has an initial version
      %{body: body, workflow_id: workflow_id} = valid_payload(project.id)

      # First provision to create the workflow
      conn = post(conn, ~p"/api/provision", body)
      assert json_response(conn, 201)

      # Get the workflow and its initial version history
      workflow = Lightning.Repo.get!(Workflow, workflow_id)
      initial_history = Lightning.WorkflowVersions.history_for(workflow)
      assert length(initial_history) == 1

      # Update only project metadata, keeping workflow unchanged
      updated_body = Map.put(body, "name", "updated-project-name")

      conn = post(conn, ~p"/api/provision", updated_body)
      assert json_response(conn, 201)

      # Verify version history unchanged since workflow content didn't change
      workflow = Lightning.Repo.get!(Workflow, workflow_id)
      version_history = Lightning.WorkflowVersions.history_for(workflow)
      assert version_history == initial_history

      # Verify project name was updated
      project = Lightning.Repo.get!(Lightning.Projects.Project, project.id)
      assert project.name == "updated-project-name"
    end

    test "returns 201 for an existing project with workflows marked for deletion",
         %{
           conn: conn
         } do
      project = insert(:project)

      _deleted_workflow =
        insert(:workflow,
          project: project,
          name: "Deleted workflow",
          deleted_at: DateTime.utc_now()
        )

      repo_connection =
        insert(:project_repo_connection, project: project)

      %{body: body} = valid_payload(project.id)

      conn =
        put_bearer(conn, repo_connection.access_token)

      assert post(conn, ~p"/api/provision", body) |> json_response(201)
    end

    @tag login_as: "superuser"
    test "allows a superuser to create a new project", %{conn: conn} do
      %{
        body: body,
        project_id: project_id,
        first_job_id: first_job_id,
        second_job_id: second_job_id,
        trigger_id: trigger_id,
        workflow_id: workflow_id,
        job_edge_id: job_edge_id
      } = valid_payload()

      conn = post(conn, ~p"/api/provision", body)
      response = json_response(conn, 201)

      assert %{
               "id" => ^project_id,
               "name" => "test-project",
               "workflows" => workflows
             } = response["data"]

      project = Lightning.Projects.get_project!(project_id)

      assert project.name == "test-project"

      workflow_ids = Enum.map(workflows, fn w -> w["id"] end)

      parent_project_ids =
        from(w in Workflow,
          where: w.id in ^workflow_ids
        )
        |> Repo.all()
        |> Enum.map(fn w -> w.project_id end)

      assert parent_project_ids |> Enum.all?(&match?(^project_id, &1)),
             "All workflows should belong to the same project"

      workflow =
        from(w in Workflow,
          preload: [:jobs, :triggers, :edges],
          where: w.id == ^workflow_id
        )
        |> Lightning.Repo.one!()

      assert workflow.name == "default"
      assert workflow.edges |> MapSet.new(& &1.id) == MapSet.new([job_edge_id])

      assert workflow.jobs |> MapSet.new(& &1.id) ==
               MapSet.new([first_job_id, second_job_id])

      assert workflow.triggers |> MapSet.new(& &1.id) == MapSet.new([trigger_id])
    end
  end
end
