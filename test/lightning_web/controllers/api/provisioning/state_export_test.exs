defmodule LightningWeb.API.ProvisioningStateExportTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  alias Lightning.Workflows.Workflow
  alias LightningWeb.API.ProvisioningJSON

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "exporting a project" do
    setup [:assign_bearer_for_api]

    test "returns a new empty project", %{
      conn: conn,
      user: user
    } do
      %{id: project_id, name: project_name} =
        insert(:project,
          project_users: [%{user_id: user.id}]
        )

      conn = get(conn, ~p"/api/provision/#{project_id}")
      response = json_response(conn, 200)

      assert %{
               "id" => ^project_id,
               "name" => ^project_name,
               "workflows" => []
             } = response["data"]
    end

    test "returns a project with collections", %{
      conn: conn,
      user: user
    } do
      %{id: project_id, name: project_name} =
        project =
        insert(:project,
          project_users: [%{user_id: user.id}]
        )

      %{id: collection_id, name: collection_name} =
        insert(:collection, project: project)

      conn = get(conn, ~p"/api/provision/#{project_id}")
      response = json_response(conn, 200)

      assert %{
               "id" => ^project_id,
               "name" => ^project_name,
               "workflows" => [],
               "collections" => collections_resp
             } = response["data"]

      assert collections_resp == [
               %{"id" => collection_id, "name" => collection_name}
             ]
    end

    test "returns a project with channels", %{
      conn: conn,
      user: user
    } do
      %{id: project_id} =
        project =
        insert(:project,
          project_users: [%{user_id: user.id}]
        )

      project_credential =
        insert(:project_credential,
          credential: %{name: "dest-cred", body: %{}, user_id: user.id},
          project: project
        )

      %{id: channel_with_cred_id} =
        channel_with_cred =
        insert(:channel,
          project: project,
          name: "with-cred",
          destination_url: "https://example.com/a",
          enabled: true
        )

      insert(:channel_auth_method,
        channel: channel_with_cred,
        role: :destination,
        webhook_auth_method: nil,
        project_credential: project_credential
      )

      %{id: channel_without_cred_id} =
        insert(:channel,
          project: project,
          name: "without-cred",
          destination_url: "https://example.com/b",
          enabled: false
        )

      conn = get(conn, ~p"/api/provision/#{project_id}")
      response = json_response(conn, 200)

      assert %{"channels" => channels_resp} = response["data"]

      expected_pc_id = project_credential.id

      assert [
               %{
                 "id" => ^channel_with_cred_id,
                 "name" => "with-cred",
                 "destination_url" => "https://example.com/a",
                 "enabled" => true,
                 "destination_credential_id" => ^expected_pc_id
               },
               %{
                 "id" => ^channel_without_cred_id,
                 "name" => "without-cred",
                 "destination_url" => "https://example.com/b",
                 "enabled" => false,
                 "destination_credential_id" => nil
               }
             ] = Enum.sort_by(channels_resp, & &1["name"])
    end

    test "returns a non empty project without credentials", %{
      conn: conn,
      user: user
    } do
      %{id: project_id, name: project_name} =
        project =
        insert(:project,
          project_users: [%{user_id: user.id}]
        )

      project_credential =
        insert(:project_credential,
          credential: %{
            name: "test credential",
            body: %{"username" => "quux", "password" => "immasecret"},
            user_id: user.id
          },
          project: project
        )

      %{
        triggers: [%{id: trigger_id}],
        edges: [%{id: edge_1_id} = edge_1],
        jobs: [%{id: job_1_id} = job_1]
      } =
        workflow =
        insert(:simple_workflow, project: project, name: "Workflow123")

      %{id: job_2_id} =
        job_2 =
        insert(:job,
          workflow: workflow,
          name: "Second Step",
          adaptor: "@openfn/language-http@latest",
          body: "fn(state => state.references)",
          workflow: workflow,
          project_credential: project_credential
        )

      %{id: edge_2_id} =
        edge_2 =
        insert(:edge,
          workflow: workflow,
          source_job: job_1,
          target_job: job_2,
          condition_type: :js_expression,
          condition_label: "sick",
          condition_expression: "data.illness === true"
        )

      %{
        "edges" => [edge_1_json, edge_2_json],
        "jobs" => [_job_1, job_2_json],
        "triggers" => [trigger_json]
      } =
        workflow_json =
        workflow
        |> Map.merge(%{jobs: [job_1, job_2], edges: [edge_1, edge_2]})
        |> ProvisioningJSON.as_json()
        |> Jason.encode!()
        |> Jason.decode!()

      assert %{
               "id" => ^edge_1_id,
               "condition_type" => "always",
               "source_trigger_id" => ^trigger_id,
               "target_job_id" => ^job_1_id,
               "enabled" => true
             } =
               edge_1_json

      refute Map.has_key?(edge_1_json, "source_job_id")
      refute Map.has_key?(edge_1_json, "condition_label")
      refute Map.has_key?(edge_1_json, "condition_expression")

      assert %{
               "id" => ^edge_2_id,
               "condition_type" => "js_expression",
               "condition_label" => "sick",
               "condition_expression" => "data.illness === true",
               "source_job_id" => ^job_1_id,
               "target_job_id" => ^job_2_id,
               "enabled" => true
             } =
               edge_2_json

      assert Map.has_key?(job_2_json, "project_credential_id")

      assert %{
               "id" => ^job_2_id,
               "name" => "Second Step",
               "adaptor" => "@openfn/language-http@latest",
               "body" => "fn(state => state.references)"
             } = job_2_json

      assert %{
               "id" => ^trigger_id,
               "type" => "webhook",
               "enabled" => true
             } = trigger_json

      conn = get(conn, ~p"/api/provision/#{project_id}")
      response = json_response(conn, 200)

      expected_hash =
        workflow
        |> Repo.preload([:jobs, :edges, :triggers], force: true)
        |> Lightning.WorkflowVersions.generate_hash()

      workflow_json = %{
        workflow_json
        | "version_history" => ["app:#{expected_hash}"]
      }

      assert %{
               "id" => ^project_id,
               "name" => ^project_name,
               "workflows" => [^workflow_json]
             } = response["data"]
    end

    test "returns a non empty project without credentials for support user", %{
      conn: conn,
      user: user
    } do
      _user = Repo.update!(Ecto.Changeset.change(user, %{support_user: true}))

      %{id: project_id, name: project_name} =
        project =
        insert(:project,
          allow_support_access: true,
          project_users: [%{user: build(:user), role: :owner}]
        )

      project_credential =
        insert(:project_credential,
          credential: %{
            name: "test credential",
            body: %{"username" => "quux", "password" => "immasecret"},
            user_id: user.id
          },
          project: project
        )

      %{
        triggers: [%{id: trigger_id}],
        edges: [%{id: edge_1_id} = edge_1],
        jobs: [%{id: job_1_id} = job_1]
      } =
        workflow =
        insert(:simple_workflow, project: project, name: "Workflow123")

      %{id: job_2_id} =
        job_2 =
        insert(:job,
          workflow: workflow,
          name: "Second Step",
          adaptor: "@openfn/language-http@latest",
          body: "fn(state => state.references)",
          workflow: workflow,
          project_credential: project_credential
        )

      %{id: edge_2_id} =
        edge_2 =
        insert(:edge,
          workflow: workflow,
          source_job: job_1,
          target_job: job_2,
          condition_type: :js_expression,
          condition_label: "sick",
          condition_expression: "data.illness === true"
        )

      %{
        "edges" => [edge_1_json, edge_2_json],
        "jobs" => [_job_1, job_2_json],
        "triggers" => [trigger_json]
      } =
        workflow_json =
        workflow
        |> Map.merge(%{jobs: [job_1, job_2], edges: [edge_1, edge_2]})
        |> ProvisioningJSON.as_json()
        |> Jason.encode!()
        |> Jason.decode!()

      assert %{
               "id" => ^edge_1_id,
               "condition_type" => "always",
               "source_trigger_id" => ^trigger_id,
               "target_job_id" => ^job_1_id,
               "enabled" => true
             } =
               edge_1_json

      refute Map.has_key?(edge_1_json, "source_job_id")
      refute Map.has_key?(edge_1_json, "condition_label")
      refute Map.has_key?(edge_1_json, "condition_expression")

      assert %{
               "id" => ^edge_2_id,
               "condition_type" => "js_expression",
               "condition_label" => "sick",
               "condition_expression" => "data.illness === true",
               "source_job_id" => ^job_1_id,
               "target_job_id" => ^job_2_id,
               "enabled" => true
             } =
               edge_2_json

      assert Map.has_key?(job_2_json, "project_credential_id")

      assert %{
               "id" => ^job_2_id,
               "name" => "Second Step",
               "adaptor" => "@openfn/language-http@latest",
               "body" => "fn(state => state.references)"
             } = job_2_json

      assert %{
               "id" => ^trigger_id,
               "type" => "webhook",
               "enabled" => true
             } = trigger_json

      conn = get(conn, ~p"/api/provision/#{project_id}")
      response = json_response(conn, 200)

      expected_hash =
        workflow
        |> Repo.preload([:jobs, :edges, :triggers], force: true)
        |> Lightning.WorkflowVersions.generate_hash()

      workflow_json = %{
        workflow_json
        | "version_history" => ["app:#{expected_hash}"]
      }

      assert %{
               "id" => ^project_id,
               "name" => ^project_name,
               "workflows" => [^workflow_json]
             } = response["data"]
    end

    test "returns a project without deleted workflows", %{
      conn: conn,
      user: user
    } do
      %{id: project_id, name: project_name} =
        project =
        insert(:project,
          project_users: [%{user_id: user.id}]
        )

      _deleted_workflow =
        insert(:workflow,
          project: project,
          name: "Deleted workflow",
          deleted_at: DateTime.utc_now()
        )

      existing_workflow =
        insert(:workflow,
          project: project,
          name: "Existing workflow",
          deleted_at: nil
        )

      conn = get(conn, ~p"/api/provision/#{project_id}")
      response = json_response(conn, 200)

      assert %{
               "id" => ^project_id,
               "name" => ^project_name,
               "workflows" => [workflow_resp]
             } = response["data"]

      assert workflow_resp["id"] == existing_workflow.id
    end

    test "includes version_history in workflow response", %{
      conn: conn,
      user: user
    } do
      %{id: project_id} =
        project =
        insert(:project,
          project_users: [%{user_id: user.id}]
        )

      workflow =
        insert(:simple_workflow, project: project, name: "Test Workflow")

      # Record some version history
      {:ok, _v1} =
        Lightning.WorkflowVersions.record_version(
          workflow,
          "aabbccddeeff",
          "app"
        )

      {:ok, _v2} =
        Lightning.WorkflowVersions.record_version(
          workflow,
          "112233445566",
          "cli"
        )

      conn = get(conn, ~p"/api/provision/#{project_id}")
      response = json_response(conn, 200)

      assert %{"workflows" => [workflow_json]} = response["data"]
      assert workflow_json["id"] == workflow.id

      # Verify version_history is included and has the expected values
      assert workflow_json["version_history"] == [
               "app:aabbccddeeff",
               "cli:112233445566"
             ]
    end

    test "automatically ensures version history for workflows without versions",
         %{
           conn: conn,
           user: user
         } do
      %{id: project_id} =
        project =
        insert(:project,
          project_users: [%{user_id: user.id}]
        )

      workflow =
        insert(:simple_workflow,
          project: project,
          name: "Workflow Without Version"
        )

      # Verify workflow has no version history initially
      initial_history = Lightning.WorkflowVersions.history_for(workflow)
      assert initial_history == []

      conn = get(conn, ~p"/api/provision/#{project_id}")
      response = json_response(conn, 200)

      assert %{"workflows" => [workflow_json]} = response["data"]
      assert workflow_json["id"] == workflow.id

      # Verify version was automatically created
      workflow = Lightning.Repo.get!(Workflow, workflow.id)
      version_history = Lightning.WorkflowVersions.history_for(workflow)
      assert length(version_history) == 1
      assert [version] = version_history
      assert String.starts_with?(version, "app:")

      # Verify version_history is included in response
      assert workflow_json["version_history"] == version_history
    end

    test "returns the project yaml to an owner's personal access token", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :owner}])

      workflow = insert(:simple_workflow, project: project)

      response =
        conn
        |> get(~p"/api/provision/yaml?#{%{id: project.id}}")
        |> response(200)

      assert response =~ workflow.name
    end
  end
end
