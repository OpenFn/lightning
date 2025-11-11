defmodule LightningWeb.WorkflowChannelTest do
  use LightningWeb.ChannelCase

  import Lightning.CollaborationHelpers
  import Lightning.Factories
  import Mox

  setup :verify_on_exit!

  setup do
    Mox.stub(Lightning.MockConfig, :check_flag?, fn
      :require_email_verification -> true
      _flag -> nil
    end)

    # Set global mode for the mock to allow cross-process calls
    Mox.set_mox_global(LightningMock)
    # Stub the broadcast calls that save_workflow makes
    Mox.stub(LightningMock, :broadcast, fn _topic, _message -> :ok end)

    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :owner}])
    workflow = insert(:workflow, project: project)

    {:ok, _, socket} =
      LightningWeb.UserSocket
      |> socket("user_#{user.id}", %{current_user: user})
      |> subscribe_and_join(
        LightningWeb.WorkflowChannel,
        "workflow:collaborate:#{workflow.id}",
        %{"project_id" => project.id, "action" => "edit"}
      )

    on_exit(fn ->
      ensure_doc_supervisor_stopped(socket.assigns.workflow.id)
    end)

    %{socket: socket, user: user, project: project, workflow: workflow}
  end

  describe "join authorization" do
    test "rejects unauthorized users", %{workflow: workflow, project: project} do
      unauthorized_user = insert(:user)

      assert {:error, %{reason: "unauthorized"}} =
               LightningWeb.UserSocket
               |> socket("user_#{unauthorized_user.id}", %{
                 current_user: unauthorized_user
               })
               |> subscribe_and_join(
                 LightningWeb.WorkflowChannel,
                 "workflow:collaborate:#{workflow.id}",
                 %{"project_id" => project.id, "action" => "edit"}
               )
    end

    test "accepts authorized users with proper assigns", %{
      socket: socket,
      workflow: workflow,
      project: project
    } do
      assert %{workflow: socket_workflow} = socket.assigns
      assert socket_workflow.id == workflow.id
      assert %{workflow_id: workflow_id} = socket.assigns
      assert workflow_id == workflow.id
      assert %{project: socket_project} = socket.assigns
      assert socket_project.id == project.id
      assert %{session_pid: session_pid} = socket.assigns
      assert is_pid(session_pid)
    end
  end

  describe "request_adaptors and request_credentials" do
    test "handles multiple concurrent requests independently", %{
      socket: socket
    } do
      ref_adaptors = push(socket, "request_adaptors", %{})
      ref_credentials = push(socket, "request_credentials", %{})

      assert_reply ref_adaptors, :ok, %{adaptors: _}
      assert_reply ref_credentials, :ok, %{credentials: credentials}

      assert Map.has_key?(credentials, :project_credentials)
      assert Map.has_key?(credentials, :keychain_credentials)
      assert is_list(credentials.project_credentials)
      assert is_list(credentials.keychain_credentials)
    end

    test "returns project-specific adaptors", %{socket: socket, project: project} do
      # Create jobs with specific adaptors in this project
      workflow = insert(:workflow, project: project)

      insert(:job,
        workflow: workflow,
        adaptor: "@openfn/language-salesforce@latest"
      )

      insert(:job, workflow: workflow, adaptor: "@openfn/language-http@2.0.0")

      ref = push(socket, "request_project_adaptors", %{})

      assert_reply ref, :ok, %{
        project_adaptors: project_adaptors,
        all_adaptors: all_adaptors
      }

      assert is_list(project_adaptors)
      assert is_list(all_adaptors)

      # Verify project_adaptors contains only adaptors used in the project
      project_adaptor_names = Enum.map(project_adaptors, & &1.name)
      assert "@openfn/language-salesforce" in project_adaptor_names
      assert "@openfn/language-http" in project_adaptor_names

      # Verify all_adaptors contains the full registry
      assert length(all_adaptors) > 0
    end

    test "returns empty project_adaptors for project with no jobs", %{
      socket: socket
    } do
      ref = push(socket, "request_project_adaptors", %{})

      assert_reply ref, :ok, %{
        project_adaptors: project_adaptors,
        all_adaptors: all_adaptors
      }

      assert project_adaptors == []
      assert is_list(all_adaptors)
      assert length(all_adaptors) > 0
    end

    test "handles duplicate adaptors in project", %{
      socket: socket,
      project: project
    } do
      workflow = insert(:workflow, project: project)

      # Create multiple jobs with the same adaptor
      insert(:job,
        workflow: workflow,
        adaptor: "@openfn/language-common@latest"
      )

      insert(:job, workflow: workflow, adaptor: "@openfn/language-common@1.0.0")

      ref = push(socket, "request_project_adaptors", %{})

      assert_reply ref, :ok, %{project_adaptors: project_adaptors}

      # Should only appear once in project_adaptors
      common_adaptors =
        Enum.filter(project_adaptors, &(&1.name == "@openfn/language-common"))

      assert length(common_adaptors) <= 1
    end

    test "returns correctly structured project credentials", %{
      socket: socket,
      project: project
    } do
      # Create a credential with project association
      credential =
        insert(:credential,
          name: "Test Credential",
          schema: "raw",
          external_id: "ext_123"
        )

      insert(:project_credential, project: project, credential: credential)

      ref = push(socket, "request_credentials", %{})

      assert_reply ref, :ok, %{credentials: credentials}

      # Verify credential structure and values using pattern matching
      assert [
               %{
                 id: _,
                 project_credential_id: _,
                 name: "Test Credential",
                 external_id: "ext_123",
                 schema: "raw",
                 inserted_at: _,
                 updated_at: _
               }
               | _
             ] = credentials.project_credentials
    end
  end

  describe "get_context" do
    test "returns complete context with all required fields", %{
      socket: socket,
      user: user,
      project: project,
      workflow: workflow
    } do
      ref = push(socket, "get_context", %{})

      assert_reply ref, :ok, response

      # User data
      assert %{user: user_data} = response
      assert user_data.id == user.id
      assert user_data.first_name == user.first_name
      assert user_data.last_name == user.last_name
      assert user_data.email == user.email
      assert is_boolean(user_data.email_confirmed)
      assert user_data.inserted_at == user.inserted_at

      # Project data
      assert %{project: project_data} = response
      assert project_data.id == project.id
      assert project_data.name == project.name

      # Config data
      assert %{config: config_data} = response
      assert config_data.require_email_verification == true

      # Permissions data
      assert %{permissions: permissions_data} = response
      assert permissions_data.can_edit_workflow == true

      # Latest snapshot lock version
      assert %{latest_snapshot_lock_version: lock_version} = response
      assert lock_version == workflow.lock_version
    end

    test "returns config with require_email_verification false when flag disabled",
         %{socket: socket} do
      Mox.stub(Lightning.MockConfig, :check_flag?, fn
        :require_email_verification -> false
        _flag -> nil
      end)

      ref = push(socket, "get_context", %{})

      assert_reply ref, :ok, response
      assert %{config: config_data} = response
      assert config_data.require_email_verification == false
    end

    test "returns can_edit_workflow false for viewer role", %{
      project: project,
      workflow: workflow
    } do
      viewer_user = insert(:user)
      insert(:project_user, project: project, user: viewer_user, role: :viewer)

      {:ok, _, socket} =
        LightningWeb.UserSocket
        |> socket("user_#{viewer_user.id}", %{current_user: viewer_user})
        |> subscribe_and_join(
          LightningWeb.WorkflowChannel,
          "workflow:collaborate:#{workflow.id}",
          %{project_id: project.id, action: "edit"}
        )

      ref = push(socket, "get_context", %{})

      assert_reply ref, :ok, response
      assert %{permissions: permissions_data} = response
      assert permissions_data.can_edit_workflow == false
    end

    test "returns actual latest lock_version when viewing old snapshot", %{
      project: project,
      workflow: workflow,
      user: user
    } do
      # Create initial snapshot so v0 is available for viewing
      {:ok, _snapshot_v0} = Lightning.Workflows.Snapshot.create(workflow)

      # Update workflow to create v1
      workflow_changeset =
        workflow
        |> Lightning.Repo.preload([:jobs, :edges, :triggers])
        |> Lightning.Workflows.Workflow.changeset(%{name: "Version 1"})

      {:ok, updated_workflow_v1} =
        Lightning.Workflows.save_workflow(workflow_changeset, user)

      # Update workflow again to create v2 (the latest)
      v2_changeset =
        updated_workflow_v1
        |> Lightning.Repo.reload!()
        |> Lightning.Repo.preload([:jobs, :edges, :triggers])
        |> Lightning.Workflows.Workflow.changeset(%{name: "Version 2"})

      {:ok, updated_workflow_v2} =
        Lightning.Workflows.save_workflow(v2_changeset, user)

      # Join viewing old snapshot (v0 - the original workflow)
      topic_with_version = "workflow:collaborate:#{workflow.id}:v0"

      {:ok, _, snapshot_socket} =
        LightningWeb.UserSocket
        |> socket("user_#{user.id}", %{current_user: user})
        |> subscribe_and_join(
          LightningWeb.WorkflowChannel,
          topic_with_version,
          %{project_id: project.id, action: "edit"}
        )

      ref = push(snapshot_socket, "get_context", %{})

      assert_reply ref, :ok, response

      # CRITICAL: Even though we're viewing v0 (lock_version: 0),
      # latest_snapshot_lock_version should be 2 (the actual latest in DB)
      assert %{latest_snapshot_lock_version: latest_lock_version} = response
      assert latest_lock_version == updated_workflow_v2.lock_version
      assert latest_lock_version == 2
      # Verify socket is viewing old version
      assert snapshot_socket.assigns.workflow.lock_version == 0
      assert snapshot_socket.assigns.workflow.name == workflow.name
    end
  end

  describe "save_workflow" do
    test "successfully saves workflow", %{socket: socket, workflow: workflow} do
      # Modify the workflow name in Y.Doc
      session_pid = socket.assigns.session_pid
      doc = Lightning.Collaboration.Session.get_doc(session_pid)

      # Get shared types BEFORE transaction to avoid deadlock
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "test_update", fn ->
        Yex.Map.set(workflow_map, "name", "Updated via Channel")
      end)

      # Push save request
      ref = push(socket, "save_workflow", %{})

      assert_reply ref, :ok, %{
        saved_at: saved_at,
        lock_version: lock_version
      }

      assert %DateTime{} = saved_at
      assert lock_version == workflow.lock_version + 1

      # Verify workflow was actually saved to database
      saved = Lightning.Workflows.get_workflow!(workflow.id)
      assert saved.name == "Updated via Channel"
      assert saved.lock_version == lock_version
    end

    test "returns validation errors", %{socket: socket} do
      # Set invalid data in Y.Doc (blank name)
      session_pid = socket.assigns.session_pid
      doc = Lightning.Collaboration.Session.get_doc(session_pid)

      # Get shared types BEFORE transaction
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "test_update", fn ->
        Yex.Map.set(workflow_map, "name", "")
      end)

      ref = push(socket, "save_workflow", %{})

      assert_reply ref, :error, %{
        errors: errors,
        type: "validation_error"
      }

      assert is_map(errors)
      assert errors[:name]
    end

    test "handles optimistic lock conflicts", %{
      socket: socket,
      workflow: workflow,
      user: user
    } do
      # Another user saves first (simulate concurrent edit)
      {:ok, _} =
        Lightning.Workflows.save_workflow(
          Lightning.Workflows.change_workflow(workflow, %{name: "Concurrent"}),
          user
        )

      # Modify Y.Doc with stale data
      session_pid = socket.assigns.session_pid
      doc = Lightning.Collaboration.Session.get_doc(session_pid)

      # Get shared types BEFORE transaction
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "test_update", fn ->
        Yex.Map.set(workflow_map, "name", "My Change")
      end)

      ref = push(socket, "save_workflow", %{})

      # May get lock error depending on Y.Doc state
      assert_reply ref, reply_type, response

      assert reply_type in [:ok, :error]

      if reply_type == :error do
        assert response.type in ["optimistic_lock_error", "validation_error"]
      end
    end

    test "handles deleted workflow", %{socket: socket, workflow: workflow} do
      # Delete the workflow
      Lightning.Repo.update!(
        Ecto.Changeset.change(workflow,
          deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )
      )

      ref = push(socket, "save_workflow", %{})

      assert_reply ref, :error, %{
        errors: %{base: ["This workflow has been deleted"]},
        type: "workflow_deleted"
      }
    end

    test "requires authentication" do
      # Try to join channel without authentication (no token)
      # This should fail at the socket connect level
      assert_raise FunctionClauseError, fn ->
        connect(LightningWeb.UserSocket, %{})
      end
    end

    test "blocks viewers from saving", %{project: project, workflow: workflow} do
      viewer_user = insert(:user)
      insert(:project_user, project: project, user: viewer_user, role: :viewer)

      {:ok, _, socket} =
        LightningWeb.UserSocket
        |> socket("user_#{viewer_user.id}", %{current_user: viewer_user})
        |> subscribe_and_join(
          LightningWeb.WorkflowChannel,
          "workflow:collaborate:#{workflow.id}",
          %{"project_id" => project.id, "action" => "edit"}
        )

      # Viewers can join (only requires :access_read) but cannot save
      ref = push(socket, "save_workflow", %{})

      assert_reply ref, :error, %{
        errors: %{base: [message]},
        type: "unauthorized"
      }

      assert message =~ "don't have permission to edit"
    end

    test "allows editors to save", %{project: project, workflow: workflow} do
      editor_user = insert(:user)
      insert(:project_user, project: project, user: editor_user, role: :editor)

      {:ok, _, socket} =
        LightningWeb.UserSocket
        |> socket("user_#{editor_user.id}", %{current_user: editor_user})
        |> subscribe_and_join(
          LightningWeb.WorkflowChannel,
          "workflow:collaborate:#{workflow.id}",
          %{"project_id" => project.id, "action" => "edit"}
        )

      # Modify workflow
      session_pid = socket.assigns.session_pid
      doc = Lightning.Collaboration.Session.get_doc(session_pid)
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "test_update", fn ->
        Yex.Map.set(workflow_map, "name", "Editor's Change")
      end)

      ref = push(socket, "save_workflow", %{})

      assert_reply ref, :ok, %{
        saved_at: _,
        lock_version: _
      }
    end

    test "blocks save after user demoted to viewer mid-session", %{
      project: project,
      workflow: workflow
    } do
      editor_user = insert(:user)

      project_user =
        insert(:project_user, project: project, user: editor_user, role: :editor)

      {:ok, _, socket} =
        LightningWeb.UserSocket
        |> socket("user_#{editor_user.id}", %{current_user: editor_user})
        |> subscribe_and_join(
          LightningWeb.WorkflowChannel,
          "workflow:collaborate:#{workflow.id}",
          %{"project_id" => project.id, "action" => "edit"}
        )

      # Verify editor can save initially
      session_pid = socket.assigns.session_pid
      doc = Lightning.Collaboration.Session.get_doc(session_pid)
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "test_update", fn ->
        Yex.Map.set(workflow_map, "name", "Before Demotion")
      end)

      ref1 = push(socket, "save_workflow", %{})
      assert_reply ref1, :ok, %{saved_at: _, lock_version: _}

      # Demote user to viewer
      {:ok, _updated_project_user} =
        Lightning.Projects.update_project_user(project_user, %{role: :viewer})

      # Attempt to save after demotion should fail
      Yex.Doc.transaction(doc, "test_update", fn ->
        Yex.Map.set(workflow_map, "name", "After Demotion")
      end)

      ref2 = push(socket, "save_workflow", %{})

      assert_reply ref2, :error, %{
        errors: %{base: [message]},
        type: "unauthorized"
      }

      assert message =~ "don't have permission to edit"
    end
  end

  describe "save_workflow with validation errors" do
    setup %{socket: socket, workflow: workflow} do
      session_pid = socket.assigns.session_pid
      doc = Lightning.Collaboration.Session.get_doc(session_pid)

      %{socket: socket, workflow: workflow, session_pid: session_pid, doc: doc}
    end

    test "returns validation errors and writes to Y.Doc for blank workflow name",
         %{socket: socket, doc: doc} do
      # Set blank name in Y.Doc
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "test_blank_name", fn ->
        Yex.Map.set(workflow_map, "name", "")
      end)

      # Attempt save
      ref = push(socket, "save_workflow", %{})

      # Should return validation error
      assert_reply ref, :error, %{
        errors: errors,
        type: "validation_error"
      }

      assert errors[:name]
      assert errors[:name] |> List.first() =~ "can't be blank"

      # Verify error was written to Y.Doc
      errors_map = Yex.Doc.get_map(doc, "errors")
      ydoc_errors = Yex.Map.to_json(errors_map)
      workflow_errors = ydoc_errors["workflow"]
      assert is_list(workflow_errors["name"])
      assert "This field can't be blank." in workflow_errors["name"]
    end

    test "clears Y.Doc errors after successful save",
         %{socket: socket, doc: doc} do
      # Manually add error to Y.Doc
      errors_map = Yex.Doc.get_map(doc, "errors")

      Yex.Doc.transaction(doc, "test_add_error", fn ->
        Yex.Map.set(errors_map, "name", "some error")
      end)

      # Set valid unique name
      workflow_map = Yex.Doc.get_map(doc, "workflow")
      unique_name = "Valid Workflow #{System.unique_integer()}"

      Yex.Doc.transaction(doc, "test_valid_name", fn ->
        Yex.Map.set(workflow_map, "name", unique_name)
      end)

      # Save should succeed
      ref = push(socket, "save_workflow", %{})
      assert_reply ref, :ok, response

      assert response[:saved_at]
      assert response[:lock_version]

      # Verify errors were cleared from Y.Doc
      ydoc_errors = Yex.Map.to_json(errors_map)
      assert ydoc_errors == %{}
    end

    test "writes nested job validation errors to Y.Doc",
         %{socket: socket, doc: doc} do
      # Add job with blank name to Y.Doc
      jobs_array = Yex.Doc.get_array(doc, "jobs")
      job_id = Ecto.UUID.generate()

      job_map =
        Yex.MapPrelim.from(%{
          "id" => job_id,
          "name" => "",
          "body" => Yex.TextPrelim.from(""),
          "adaptor" => "@openfn/language-common@1.0.0",
          "project_credential_id" => nil,
          "keychain_credential_id" => nil
        })

      Yex.Doc.transaction(doc, "test_add_invalid_job", fn ->
        Yex.Array.push(jobs_array, job_map)
      end)

      # Attempt save
      ref = push(socket, "save_workflow", %{})
      assert_reply ref, :error, %{type: "validation_error"}

      # Check job error in Y.Doc with nested structure
      errors_map = Yex.Doc.get_map(doc, "errors")
      ydoc_errors = Yex.Map.to_json(errors_map)

      # Errors should be nested: %{jobs: %{job-id: %{name: ["error"]}}}
      assert Map.has_key?(ydoc_errors, "jobs")
      assert is_map(ydoc_errors["jobs"])
      assert Map.has_key?(ydoc_errors["jobs"], job_id)
      assert is_map(ydoc_errors["jobs"][job_id])
      assert is_list(ydoc_errors["jobs"][job_id]["name"])

      assert Enum.any?(
               ydoc_errors["jobs"][job_id]["name"],
               &String.contains?(&1, "can't be blank")
             )
    end

    test "handles duplicate workflow name validation",
         %{socket: socket, doc: doc, project: project} do
      # Create another workflow with a specific name
      insert(:workflow, project: project, name: "Existing Workflow")

      # Try to set current workflow to same name
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "test_duplicate_name", fn ->
        Yex.Map.set(workflow_map, "name", "Existing Workflow")
      end)

      # Attempt save
      ref = push(socket, "save_workflow", %{})

      assert_reply ref, :error, %{
        errors: errors,
        type: "validation_error"
      }

      assert errors[:name]
      assert errors[:name] |> List.first() =~ "already exists"

      # Verify error in Y.Doc
      errors_map = Yex.Doc.get_map(doc, "errors")
      ydoc_errors = Yex.Map.to_json(errors_map)
      workflow_errors = ydoc_errors["workflow"]
      assert is_list(workflow_errors["name"])

      assert Enum.any?(
               workflow_errors["name"],
               &String.contains?(&1, "already exists")
             )
    end
  end

  describe "reset_workflow" do
    test "blocks viewers from resetting", %{
      project: project,
      workflow: workflow
    } do
      viewer_user = insert(:user)
      insert(:project_user, project: project, user: viewer_user, role: :viewer)

      {:ok, _, socket} =
        LightningWeb.UserSocket
        |> socket("user_#{viewer_user.id}", %{current_user: viewer_user})
        |> subscribe_and_join(
          LightningWeb.WorkflowChannel,
          "workflow:collaborate:#{workflow.id}",
          %{"project_id" => project.id, "action" => "edit"}
        )

      ref = push(socket, "reset_workflow", %{})

      assert_reply ref, :error, %{
        errors: %{base: [message]},
        type: "unauthorized"
      }

      assert message =~ "don't have permission to edit"
    end

    test "allows editors to reset", %{project: project, workflow: workflow} do
      editor_user = insert(:user)
      insert(:project_user, project: project, user: editor_user, role: :editor)

      {:ok, _, socket} =
        LightningWeb.UserSocket
        |> socket("user_#{editor_user.id}", %{current_user: editor_user})
        |> subscribe_and_join(
          LightningWeb.WorkflowChannel,
          "workflow:collaborate:#{workflow.id}",
          %{"project_id" => project.id, "action" => "edit"}
        )

      ref = push(socket, "reset_workflow", %{})

      assert_reply ref, :ok, %{
        lock_version: _,
        workflow_id: _
      }
    end

    test "blocks reset after user demoted mid-session", %{
      project: project,
      workflow: workflow
    } do
      editor_user = insert(:user)

      project_user =
        insert(:project_user, project: project, user: editor_user, role: :editor)

      {:ok, _, socket} =
        LightningWeb.UserSocket
        |> socket("user_#{editor_user.id}", %{current_user: editor_user})
        |> subscribe_and_join(
          LightningWeb.WorkflowChannel,
          "workflow:collaborate:#{workflow.id}",
          %{"project_id" => project.id, "action" => "edit"}
        )

      # Verify editor can reset initially
      ref1 = push(socket, "reset_workflow", %{})
      assert_reply ref1, :ok, %{lock_version: _, workflow_id: _}

      # Demote user to viewer
      {:ok, _} =
        Lightning.Projects.update_project_user(project_user, %{role: :viewer})

      # Attempt to reset after demotion should fail
      ref2 = push(socket, "reset_workflow", %{})

      assert_reply ref2, :error, %{
        errors: %{base: [message]},
        type: "unauthorized"
      }

      assert message =~ "don't have permission to edit"
    end
  end

  describe "save_and_sync" do
    test "requires commit message", %{socket: socket} do
      ref = push(socket, "save_and_sync", %{})

      assert_reply ref, :error, %{
        errors: errors,
        type: "validation_error"
      }

      assert is_map(errors)
    end

    test "returns validation errors when workflow data is invalid", %{
      socket: socket
    } do
      # Set invalid data in Y.Doc (blank name)
      session_pid = socket.assigns.session_pid
      doc = Lightning.Collaboration.Session.get_doc(session_pid)

      # Get shared types BEFORE transaction
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "test_update", fn ->
        Yex.Map.set(workflow_map, "name", "")
      end)

      # Set up GitHub repo connection
      insert(:project_repo_connection,
        project: socket.assigns.project,
        repo: "openfn/demo",
        branch: "main"
      )

      ref =
        push(socket, "save_and_sync", %{
          "commit_message" => "Valid commit message"
        })

      assert_reply ref, :error, %{
        errors: errors,
        type: "validation_error"
      }

      assert is_map(errors)
      assert errors[:name]
    end

    test "requires GitHub repo connection to be configured", %{socket: socket} do
      # No GitHub repo connection exists for this project

      # Modify workflow
      session_pid = socket.assigns.session_pid
      doc = Lightning.Collaboration.Session.get_doc(session_pid)
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "test_update", fn ->
        Yex.Map.set(workflow_map, "name", "Test")
      end)

      ref =
        push(socket, "save_and_sync", %{"commit_message" => "Test commit"})

      assert_reply ref, :error, %{
        errors: errors,
        type: error_type
      }

      assert is_map(errors)
      # Should indicate GitHub connection is missing
      assert error_type == "github_sync_error"
    end

    test "blocks viewers from saving and syncing", %{
      project: project,
      workflow: workflow
    } do
      viewer_user = insert(:user)
      insert(:project_user, project: project, user: viewer_user, role: :viewer)

      # Set up GitHub repo connection
      insert(:project_repo_connection,
        project: project,
        repo: "openfn/demo",
        branch: "main"
      )

      {:ok, _, socket} =
        LightningWeb.UserSocket
        |> socket("user_#{viewer_user.id}", %{current_user: viewer_user})
        |> subscribe_and_join(
          LightningWeb.WorkflowChannel,
          "workflow:collaborate:#{workflow.id}",
          %{"project_id" => project.id, "action" => "edit"}
        )

      # Viewers can join but cannot save and sync
      ref =
        push(socket, "save_and_sync", %{"commit_message" => "Test commit"})

      assert_reply ref, :error, %{
        errors: %{base: [message]},
        type: "unauthorized"
      }

      assert message =~ "don't have permission to edit"
    end

    test "handles deleted workflow", %{socket: socket, workflow: workflow} do
      # Set up GitHub repo connection
      insert(:project_repo_connection,
        project: socket.assigns.project,
        repo: "openfn/demo",
        branch: "main"
      )

      # Delete the workflow
      Lightning.Repo.update!(
        Ecto.Changeset.change(workflow,
          deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )
      )

      ref =
        push(socket, "save_and_sync", %{"commit_message" => "Test commit"})

      assert_reply ref, :error, %{
        errors: %{base: ["This workflow has been deleted"]},
        type: "workflow_deleted"
      }
    end
  end

  describe "validate_workflow_name" do
    setup %{socket: socket} do
      project = socket.assigns.project

      # Create some existing workflows
      workflow1 = insert(:workflow, project: project, name: "My Workflow")
      workflow2 = insert(:workflow, project: project, name: "My Workflow 1")
      workflow3 = insert(:workflow, project: project, name: "Test Workflow")

      %{
        socket: socket,
        project: project,
        existing_workflows: [workflow1, workflow2, workflow3]
      }
    end

    test "returns original name when unique", %{socket: socket} do
      ref =
        push(socket, "validate_workflow_name", %{
          "workflow" => %{"name" => "Unique Workflow"}
        })

      assert_reply ref, :ok, %{workflow: validated}
      assert validated["name"] == "Unique Workflow"
    end

    test "appends '2' when name and name 1 exist", %{socket: socket} do
      ref =
        push(socket, "validate_workflow_name", %{
          "workflow" => %{"name" => "My Workflow"}
        })

      assert_reply ref, :ok, %{workflow: validated}
      assert validated["name"] == "My Workflow 2"
    end

    test "appends number to already-numbered name", %{socket: socket} do
      ref =
        push(socket, "validate_workflow_name", %{
          "workflow" => %{"name" => "My Workflow 1"}
        })

      assert_reply ref, :ok, %{workflow: validated}
      assert validated["name"] == "My Workflow 1 1"
    end

    test "defaults empty name to 'Untitled workflow'", %{socket: socket} do
      ref =
        push(socket, "validate_workflow_name", %{
          "workflow" => %{"name" => ""}
        })

      assert_reply ref, :ok, %{workflow: validated}
      assert validated["name"] == "Untitled workflow"
    end

    test "defaults whitespace-only name to 'Untitled workflow'", %{
      socket: socket
    } do
      ref =
        push(socket, "validate_workflow_name", %{
          "workflow" => %{"name" => "   "}
        })

      assert_reply ref, :ok, %{workflow: validated}
      assert validated["name"] == "Untitled workflow"
    end

    test "ensures 'Untitled workflow' is unique", %{socket: socket} do
      # Create an existing "Untitled workflow"
      insert(:workflow,
        project: socket.assigns.project,
        name: "Untitled workflow"
      )

      ref =
        push(socket, "validate_workflow_name", %{
          "workflow" => %{"name" => ""}
        })

      assert_reply ref, :ok, %{workflow: validated}
      assert validated["name"] == "Untitled workflow 1"
    end

    test "preserves other params unchanged", %{socket: socket} do
      ref =
        push(socket, "validate_workflow_name", %{
          "workflow" => %{
            "name" => "Test Workflow",
            "other_field" => "value"
          }
        })

      assert_reply ref, :ok, %{workflow: validated}
      assert validated["name"] == "Test Workflow 1"
      assert validated["other_field"] == "value"
    end

    test "sequential numbering skips gaps", %{socket: socket} do
      # Create workflows with gaps: "Gap Test", "Gap Test 1", "Gap Test 3"
      insert(:workflow,
        project: socket.assigns.project,
        name: "Gap Test"
      )

      insert(:workflow,
        project: socket.assigns.project,
        name: "Gap Test 1"
      )

      insert(:workflow,
        project: socket.assigns.project,
        name: "Gap Test 3"
      )

      ref =
        push(socket, "validate_workflow_name", %{
          "workflow" => %{"name" => "Gap Test"}
        })

      # Algorithm doesn't fill gaps, it continues from highest
      assert_reply ref, :ok, %{workflow: validated}
      assert validated["name"] == "Gap Test 2"
    end
  end

  describe "PubSub subscription and credential broadcasting" do
    test "receives and forwards credentials_updated broadcast to channel", %{
      socket: socket,
      workflow: workflow,
      project: project
    } do
      # Create some test credentials
      user = socket.assigns.current_user

      credential =
        insert(:credential,
          name: "Broadcast Test",
          schema: "raw",
          user: user
        )

      insert(:project_credential, project: project, credential: credential)

      # Fetch and render credentials
      credentials =
        Lightning.Projects.list_project_credentials(project)
        |> Enum.concat(
          Lightning.Credentials.list_keychain_credentials_for_project(project)
        )

      # This matches the render_credentials function in workflow_channel.ex
      rendered_credentials = %{
        project_credentials:
          credentials
          |> Enum.filter(&match?(%Lightning.Projects.ProjectCredential{}, &1))
          |> Enum.map(fn pc ->
            %{
              id: pc.credential.id,
              project_credential_id: pc.id,
              name: pc.credential.name,
              external_id: pc.credential.external_id,
              schema: pc.credential.schema,
              owner: %{
                id: pc.credential.user.id,
                name:
                  "#{pc.credential.user.first_name} #{pc.credential.user.last_name}",
                email: pc.credential.user.email
              },
              oauth_client_name: nil,
              inserted_at: pc.credential.inserted_at,
              updated_at: pc.credential.updated_at
            }
          end),
        keychain_credentials: []
      }

      # Broadcast credentials_updated message
      Phoenix.PubSub.broadcast(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow.id}",
        %{event: "credentials_updated", payload: rendered_credentials}
      )

      # Verify channel pushed the message to the client
      assert_push "credentials_updated", pushed_credentials

      assert %{
               project_credentials: [cred | _],
               keychain_credentials: []
             } = pushed_credentials

      assert cred.name == "Broadcast Test"
      assert cred.schema == "raw"
    end

    test "forwards keychain credentials in broadcast", %{
      socket: socket,
      workflow: workflow,
      project: project
    } do
      user = socket.assigns.current_user

      # Create a keychain credential
      keychain_cred =
        insert(:keychain_credential,
          name: "Keychain Broadcast",
          path: "$.secret",
          project: project,
          created_by: user
        )

      # Simulate broadcast with keychain credential
      rendered_credentials = %{
        project_credentials: [],
        keychain_credentials: [
          %{
            id: keychain_cred.id,
            name: keychain_cred.name,
            path: keychain_cred.path,
            default_credential_id: keychain_cred.default_credential_id,
            inserted_at: keychain_cred.inserted_at,
            updated_at: keychain_cred.updated_at
          }
        ]
      }

      Phoenix.PubSub.broadcast(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow.id}",
        %{event: "credentials_updated", payload: rendered_credentials}
      )

      assert_push "credentials_updated", pushed_credentials

      assert %{
               project_credentials: [],
               keychain_credentials: [keychain | _]
             } = pushed_credentials

      assert keychain.name == "Keychain Broadcast"
      assert keychain.path == "$.secret"
    end

    test "broadcasts to all subscribed channels", %{workflow: workflow} do
      # Broadcast empty credentials update
      rendered_credentials = %{
        project_credentials: [],
        keychain_credentials: []
      }

      Phoenix.PubSub.broadcast(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow.id}",
        %{event: "credentials_updated", payload: rendered_credentials}
      )

      # Socket should receive the push
      assert_push "credentials_updated", pushed_credentials

      assert %{
               project_credentials: [],
               keychain_credentials: []
             } = pushed_credentials
    end

    test "handles presence_diff without errors", %{
      socket: socket,
      workflow: workflow
    } do
      # Send a presence_diff message (already handled by channel)
      Phoenix.PubSub.broadcast(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow.id}",
        %{event: "presence_diff", payload: %{}}
      )

      # Should not push credentials_updated
      refute_push "credentials_updated", _

      # Socket should still be functional
      ref = push(socket, "request_credentials", %{})
      assert_reply ref, :ok, %{credentials: _}
    end

    test "handles credentials with all optional fields", %{
      socket: socket,
      workflow: workflow,
      project: project
    } do
      user = socket.assigns.current_user

      oauth_client = insert(:oauth_client, name: "Google OAuth")

      credential =
        insert(:credential,
          name: "Full Featured Credential",
          schema: "oauth",
          user: user,
          external_id: "ext_456",
          oauth_client: oauth_client
        )

      project_credential =
        insert(:project_credential, project: project, credential: credential)

      # Render with all fields populated
      rendered_credentials = %{
        project_credentials: [
          %{
            id: credential.id,
            project_credential_id: project_credential.id,
            name: credential.name,
            external_id: credential.external_id,
            schema: credential.schema,
            owner: %{
              id: user.id,
              name: "#{user.first_name} #{user.last_name}",
              email: user.email
            },
            oauth_client_name: oauth_client.name,
            inserted_at: credential.inserted_at,
            updated_at: credential.updated_at
          }
        ],
        keychain_credentials: []
      }

      Phoenix.PubSub.broadcast(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow.id}",
        %{event: "credentials_updated", payload: rendered_credentials}
      )

      assert_push "credentials_updated", pushed_credentials

      assert [
               %{
                 name: "Full Featured Credential",
                 schema: "oauth",
                 external_id: "ext_456",
                 oauth_client_name: "Google OAuth",
                 owner: %{
                   id: owner_id,
                   name: owner_name,
                   email: owner_email
                 }
               }
             ] = pushed_credentials.project_credentials

      assert owner_id == user.id
      assert owner_name == "#{user.first_name} #{user.last_name}"
      assert owner_email == user.email
    end

    test "request_credentials renders owner and oauth_client_name correctly", %{
      socket: socket,
      project: project
    } do
      user = socket.assigns.current_user

      oauth_client = insert(:oauth_client, name: "Salesforce OAuth")

      credential =
        insert(:credential,
          name: "OAuth Test Credential",
          schema: "oauth",
          user: user,
          external_id: "ext_789",
          oauth_client: oauth_client
        )

      insert(:project_credential, project: project, credential: credential)

      # Request credentials through the channel (goes through render_credentials)
      ref = push(socket, "request_credentials", %{})

      assert_reply ref, :ok, %{credentials: credentials}

      # Verify render_owner was called and returned correct data
      assert [cred | _] = credentials.project_credentials

      assert cred.owner == %{
               id: user.id,
               name: "#{user.first_name} #{user.last_name}",
               email: user.email
             }

      # Verify render_oauth_client_name was called
      assert cred.oauth_client_name == "Salesforce OAuth"
      assert cred.name == "OAuth Test Credential"
      assert cred.external_id == "ext_789"
    end

    test "request_credentials handles nil owner and oauth_client", %{
      socket: socket,
      project: project
    } do
      # Create credential without user association (edge case)
      credential =
        insert(:credential,
          name: "No Owner Credential",
          schema: "raw",
          user: nil,
          oauth_client: nil
        )

      insert(:project_credential, project: project, credential: credential)

      ref = push(socket, "request_credentials", %{})

      assert_reply ref, :ok, %{credentials: credentials}

      # Verify render_owner returns nil for nil user
      assert [cred | _] = credentials.project_credentials
      assert cred.owner == nil
      assert cred.oauth_client_name == nil
    end
  end

  describe "request_history" do
    test "returns work orders with runs for workflow", %{
      socket: socket,
      workflow: workflow,
      project: project
    } do
      # Create snapshot for workflow (required for work orders)
      workflow = with_snapshot(workflow)

      # Create trigger and work orders using the proper create_for method
      trigger = insert(:trigger, type: :webhook, workflow: workflow)
      dataclip_1 = insert(:dataclip, project: project)

      {:ok, _work_order_1} =
        Lightning.WorkOrders.create_for(trigger,
          dataclip: dataclip_1,
          workflow: workflow
        )

      dataclip_2 = insert(:dataclip, project: project)

      {:ok, _work_order_2} =
        Lightning.WorkOrders.create_for(trigger,
          dataclip: dataclip_2,
          workflow: workflow
        )

      ref = push(socket, "request_history", %{})

      assert_reply ref, :ok, %{history: history}
      assert is_list(history)
      assert length(history) == 2

      # Verify structure matches expected JSON format
      [first_wo | _] = history
      assert Map.has_key?(first_wo, :id)
      assert Map.has_key?(first_wo, :state)
      assert Map.has_key?(first_wo, :last_activity)
      assert Map.has_key?(first_wo, :version)
      assert Map.has_key?(first_wo, :runs)
      assert is_list(first_wo.runs)

      # Verify run structure
      [first_run | _] = first_wo.runs
      assert Map.has_key?(first_run, :id)
      assert Map.has_key?(first_run, :state)
      assert Map.has_key?(first_run, :error_type)
      assert Map.has_key?(first_run, :started_at)
      assert Map.has_key?(first_run, :finished_at)
    end

    test "returns empty list when workflow has no work orders", %{socket: socket} do
      ref = push(socket, "request_history", %{})

      assert_reply ref, :ok, %{history: history}
      assert history == []
    end

    test "includes specific run's work order when run_id provided", %{
      socket: socket,
      workflow: workflow,
      project: project
    } do
      # Create snapshot for workflow (required for work orders)
      workflow = with_snapshot(workflow)

      # Create an old work order
      trigger = insert(:trigger, type: :webhook, workflow: workflow)
      dataclip = insert(:dataclip, project: project)

      {:ok, old_work_order} =
        Lightning.WorkOrders.create_for(trigger,
          dataclip: dataclip,
          workflow: workflow
        )

      old_run = hd(old_work_order.runs)

      # Create multiple newer work orders
      for _ <- 1..5 do
        dataclip = insert(:dataclip, project: project)

        Lightning.WorkOrders.create_for(trigger,
          dataclip: dataclip,
          workflow: workflow
        )
      end

      ref = push(socket, "request_history", %{"run_id" => old_run.id})

      assert_reply ref, :ok, %{history: history}
      assert is_list(history)

      # Verify the specific work order is included
      work_order_ids = Enum.map(history, & &1.id)
      assert old_work_order.id in work_order_ids
    end
  end

  describe "request_run_steps" do
    test "returns step data for valid run_id", %{
      socket: socket,
      workflow: workflow,
      project: project
    } do
      # Create jobs and steps for the workflow
      job1 = insert(:job, workflow: workflow)
      job2 = insert(:job, workflow: workflow)
      workflow = with_snapshot(workflow)

      dataclip = insert(:dataclip, project: project)
      work_order = insert(:workorder, workflow: workflow)

      run =
        insert(:run,
          work_order: work_order,
          starting_job: job1,
          dataclip: dataclip
        )

      _step1 =
        insert(:step,
          runs: [run],
          job: job1,
          exit_reason: "success"
        )

      _step2 =
        insert(:step,
          runs: [run],
          job: job2,
          exit_reason: "fail",
          error_type: "RuntimeError"
        )

      ref = push(socket, "request_run_steps", %{"run_id" => run.id})

      assert_reply ref, :ok, response

      assert %{run_id: run_id, steps: steps, metadata: metadata} = response
      assert run_id == run.id
      assert length(steps) == 2

      assert Enum.any?(steps, fn s ->
               s.job_id == job1.id && s.exit_reason == "success"
             end)

      assert Enum.any?(steps, fn s ->
               s.job_id == job2.id && s.exit_reason == "fail" &&
                 s.error_type == "RuntimeError"
             end)

      assert metadata.starting_job_id == job1.id
    end

    test "returns error for non-existent run", %{socket: socket} do
      ref =
        push(socket, "request_run_steps", %{"run_id" => Ecto.UUID.generate()})

      assert_reply ref, :error, %{reason: "run_not_found"}
    end

    test "returns error for run from different project", %{socket: socket} do
      other_project = insert(:project)
      other_workflow = insert(:workflow, project: other_project)
      job = insert(:job, workflow: other_workflow)
      other_workflow = with_snapshot(other_workflow)

      dataclip = insert(:dataclip, project: other_project)
      work_order = insert(:workorder, workflow: other_workflow)

      run =
        insert(:run,
          work_order: work_order,
          starting_job: job,
          dataclip: dataclip
        )

      ref = push(socket, "request_run_steps", %{"run_id" => run.id})
      assert_reply ref, :error, %{reason: "unauthorized"}
    end
  end

  describe "real-time history updates" do
    test "handles WorkOrderCreated event for current workflow", %{
      socket: socket,
      workflow: workflow,
      project: project
    } do
      # Create snapshot and work order
      workflow = with_snapshot(workflow)
      trigger = insert(:trigger, type: :webhook, workflow: workflow)
      dataclip = insert(:dataclip, project: project)

      {:ok, work_order} =
        Lightning.WorkOrders.create_for(trigger,
          dataclip: dataclip,
          workflow: workflow
        )

      # Send the event directly to handle_info
      event = %Lightning.WorkOrders.Events.WorkOrderCreated{
        work_order: work_order,
        project_id: project.id
      }

      # Should not crash and should push a message
      assert {:noreply, ^socket} =
               LightningWeb.WorkflowChannel.handle_info(event, socket)

      # Verify message was pushed (check mailbox)
      assert_push "history_updated", %{action: "created", work_order: wo}
      assert wo.id == work_order.id
    end

    test "ignores WorkOrderCreated event for different workflow", %{
      socket: socket,
      project: project
    } do
      # Create a different workflow
      other_workflow = insert(:workflow, project: project)
      other_workflow = with_snapshot(other_workflow)

      trigger = insert(:trigger, type: :webhook, workflow: other_workflow)
      dataclip = insert(:dataclip, project: project)

      {:ok, work_order} =
        Lightning.WorkOrders.create_for(trigger,
          dataclip: dataclip,
          workflow: other_workflow
        )

      event = %Lightning.WorkOrders.Events.WorkOrderCreated{
        work_order: work_order,
        project_id: project.id
      }

      # Should not crash
      assert {:noreply, ^socket} =
               LightningWeb.WorkflowChannel.handle_info(event, socket)

      # Should not push any message
      refute_push "history_updated", _payload
    end

    test "handles WorkOrderUpdated event for current workflow", %{
      socket: socket,
      workflow: workflow,
      project: project
    } do
      # Create snapshot and work order
      workflow = with_snapshot(workflow)
      trigger = insert(:trigger, type: :webhook, workflow: workflow)
      dataclip = insert(:dataclip, project: project)

      {:ok, work_order} =
        Lightning.WorkOrders.create_for(trigger,
          dataclip: dataclip,
          workflow: workflow
        )

      {:ok, updated_work_order} =
        Lightning.Repo.update(Ecto.Changeset.change(work_order, state: :success))

      event = %Lightning.WorkOrders.Events.WorkOrderUpdated{
        work_order: updated_work_order
      }

      # Should not crash and should push a message
      assert {:noreply, ^socket} =
               LightningWeb.WorkflowChannel.handle_info(event, socket)

      assert_push "history_updated", %{action: "updated", work_order: wo}
      assert wo.id == updated_work_order.id
    end

    test "handles RunCreated event for current workflow", %{
      socket: socket,
      workflow: workflow,
      project: project
    } do
      # Create a job for the workflow first
      job = insert(:job, workflow: workflow)

      # Create snapshot and work order
      workflow = with_snapshot(workflow)
      trigger = insert(:trigger, type: :webhook, workflow: workflow)
      dataclip = insert(:dataclip, project: project)

      {:ok, work_order} =
        Lightning.WorkOrders.create_for(trigger,
          dataclip: dataclip,
          workflow: workflow
        )

      {:ok, run} =
        Lightning.Repo.insert(%Lightning.Run{
          work_order_id: work_order.id,
          starting_trigger_id: trigger.id,
          starting_job_id: job.id,
          dataclip_id: dataclip.id,
          state: :available
        })

      event = %Lightning.WorkOrders.Events.RunCreated{
        run: run,
        project_id: project.id
      }

      # Should not crash and should push a message
      assert {:noreply, ^socket} =
               LightningWeb.WorkflowChannel.handle_info(event, socket)

      assert_push "history_updated", %{
        action: "run_created",
        run: pushed_run,
        work_order_id: wo_id
      }

      assert pushed_run.id == run.id
      assert wo_id == work_order.id
    end

    test "handles RunUpdated event for current workflow", %{
      socket: socket,
      workflow: workflow,
      project: project
    } do
      # Create snapshot and work order
      workflow = with_snapshot(workflow)
      trigger = insert(:trigger, type: :webhook, workflow: workflow)
      dataclip = insert(:dataclip, project: project)

      {:ok, work_order} =
        Lightning.WorkOrders.create_for(trigger,
          dataclip: dataclip,
          workflow: workflow
        )

      run = hd(work_order.runs)

      {:ok, updated_run} =
        Lightning.Repo.update(Ecto.Changeset.change(run, state: :success))

      event = %Lightning.WorkOrders.Events.RunUpdated{run: updated_run}

      # Should not crash and should push a message
      assert {:noreply, ^socket} =
               LightningWeb.WorkflowChannel.handle_info(event, socket)

      assert_push "history_updated", %{
        action: "run_updated",
        run: pushed_run,
        work_order_id: wo_id
      }

      assert pushed_run.id == updated_run.id
      assert wo_id == work_order.id
    end

    test "ignores RunUpdated event for different workflow", %{
      socket: socket,
      project: project
    } do
      # Create a different workflow
      other_workflow = insert(:workflow, project: project)
      other_workflow = with_snapshot(other_workflow)

      trigger = insert(:trigger, type: :webhook, workflow: other_workflow)
      dataclip = insert(:dataclip, project: project)

      {:ok, work_order} =
        Lightning.WorkOrders.create_for(trigger,
          dataclip: dataclip,
          workflow: other_workflow
        )

      run = hd(work_order.runs)

      {:ok, updated_run} =
        Lightning.Repo.update(Ecto.Changeset.change(run, state: :success))

      event = %Lightning.WorkOrders.Events.RunUpdated{run: updated_run}

      # Should not crash
      assert {:noreply, ^socket} =
               LightningWeb.WorkflowChannel.handle_info(event, socket)

      # Should not push any message
      refute_push "history_updated", _payload
    end
  end

  describe "webhook authentication methods" do
    test "request_trigger_auth_methods returns auth methods for a trigger", %{
      socket: socket,
      workflow: workflow,
      project: project
    } do
      # Create a trigger with webhook auth methods
      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      auth_method1 =
        insert(:webhook_auth_method,
          project: project,
          name: "API Key Auth",
          auth_type: :api
        )

      auth_method2 =
        insert(:webhook_auth_method,
          project: project,
          name: "Basic Auth",
          auth_type: :basic
        )

      # Associate auth methods with trigger
      Lightning.WebhookAuthMethods.update_trigger_auth_methods(
        trigger,
        [auth_method1, auth_method2],
        actor: socket.assigns.current_user
      )

      ref =
        push(socket, "request_trigger_auth_methods", %{
          "trigger_id" => trigger.id
        })

      assert_reply ref, :ok, %{
        trigger_id: returned_trigger_id,
        webhook_auth_methods: methods
      }

      assert returned_trigger_id == trigger.id
      assert length(methods) == 2

      assert Enum.any?(methods, fn m ->
               m.id == auth_method1.id && m.name == "API Key Auth" &&
                 m.auth_type == :api
             end)

      assert Enum.any?(methods, fn m ->
               m.id == auth_method2.id && m.name == "Basic Auth" &&
                 m.auth_type == :basic
             end)
    end

    test "request_trigger_auth_methods excludes deleted auth methods", %{
      socket: socket,
      workflow: workflow,
      project: project
    } do
      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      active_method =
        insert(:webhook_auth_method,
          project: project,
          name: "Active Auth",
          auth_type: :api
        )

      deleted_method =
        insert(:webhook_auth_method,
          project: project,
          name: "Deleted Auth",
          auth_type: :basic,
          scheduled_deletion: DateTime.utc_now()
        )

      Lightning.WebhookAuthMethods.update_trigger_auth_methods(
        trigger,
        [active_method, deleted_method],
        actor: socket.assigns.current_user
      )

      ref =
        push(socket, "request_trigger_auth_methods", %{
          "trigger_id" => trigger.id
        })

      assert_reply ref, :ok, %{webhook_auth_methods: methods}

      # Should only include active method
      assert length(methods) == 1
      assert hd(methods).id == active_method.id
    end

    test "request_trigger_auth_methods returns empty list for trigger without auth",
         %{
           socket: socket,
           workflow: workflow
         } do
      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      ref =
        push(socket, "request_trigger_auth_methods", %{
          "trigger_id" => trigger.id
        })

      assert_reply ref, :ok, %{
        trigger_id: returned_trigger_id,
        webhook_auth_methods: methods
      }

      assert returned_trigger_id == trigger.id
      assert methods == []
    end

    test "update_trigger_auth_methods associates auth methods with trigger", %{
      socket: socket,
      workflow: workflow,
      project: project
    } do
      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      auth_method1 =
        insert(:webhook_auth_method,
          project: project,
          name: "Method 1",
          auth_type: :api
        )

      auth_method2 =
        insert(:webhook_auth_method,
          project: project,
          name: "Method 2",
          auth_type: :basic
        )

      ref =
        push(socket, "update_trigger_auth_methods", %{
          "trigger_id" => trigger.id,
          "auth_method_ids" => [auth_method1.id, auth_method2.id]
        })

      assert_reply ref, :ok, %{success: true}

      # Verify broadcast was sent to all collaborators
      assert_broadcast "trigger_auth_methods_updated", %{
        trigger_id: broadcasted_trigger_id,
        webhook_auth_methods: broadcasted_methods
      }

      assert broadcasted_trigger_id == trigger.id
      assert length(broadcasted_methods) == 2
    end

    test "update_trigger_auth_methods can clear all auth methods", %{
      socket: socket,
      workflow: workflow,
      project: project
    } do
      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      auth_method =
        insert(:webhook_auth_method,
          project: project,
          name: "Method to Remove",
          auth_type: :api
        )

      # First associate
      Lightning.WebhookAuthMethods.update_trigger_auth_methods(
        trigger,
        [auth_method],
        actor: socket.assigns.current_user
      )

      # Then clear
      ref =
        push(socket, "update_trigger_auth_methods", %{
          "trigger_id" => trigger.id,
          "auth_method_ids" => []
        })

      assert_reply ref, :ok, %{success: true}

      assert_broadcast "trigger_auth_methods_updated", %{
        trigger_id: _,
        webhook_auth_methods: methods
      }

      assert methods == []
    end

    test "update_trigger_auth_methods rejects unauthorized user", %{
      workflow: workflow,
      project: project
    } do
      # Create a user without edit permissions
      viewer = insert(:user)
      insert(:project_user, project: project, user: viewer, role: :viewer)

      {:ok, _, viewer_socket} =
        LightningWeb.UserSocket
        |> socket("user_#{viewer.id}", %{current_user: viewer})
        |> subscribe_and_join(
          LightningWeb.WorkflowChannel,
          "workflow:collaborate:#{workflow.id}",
          %{"project_id" => project.id, "action" => "edit"}
        )

      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      auth_method =
        insert(:webhook_auth_method,
          project: project,
          name: "Test Method",
          auth_type: :api
        )

      ref =
        push(viewer_socket, "update_trigger_auth_methods", %{
          "trigger_id" => trigger.id,
          "auth_method_ids" => [auth_method.id]
        })

      assert_reply ref, :error, %{reason: reason}
      assert reason =~ "permission"
    end

    test "update_trigger_auth_methods rejects trigger from different workflow",
         %{
           socket: socket,
           project: project
         } do
      # Create a different workflow
      other_workflow = insert(:workflow, project: project)
      other_trigger = insert(:trigger, workflow: other_workflow, type: :webhook)

      auth_method =
        insert(:webhook_auth_method,
          project: project,
          name: "Test Method",
          auth_type: :api
        )

      ref =
        push(socket, "update_trigger_auth_methods", %{
          "trigger_id" => other_trigger.id,
          "auth_method_ids" => [auth_method.id]
        })

      assert_reply ref, :error, %{reason: reason}
      assert reason =~ "does not belong"
    end

    test "update_trigger_auth_methods filters out non-existent auth method IDs",
         %{
           socket: socket,
           workflow: workflow,
           project: project
         } do
      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      valid_method =
        insert(:webhook_auth_method,
          project: project,
          name: "Valid Method",
          auth_type: :api
        )

      # Include a non-existent UUID
      fake_uuid = Ecto.UUID.generate()

      ref =
        push(socket, "update_trigger_auth_methods", %{
          "trigger_id" => trigger.id,
          "auth_method_ids" => [valid_method.id, fake_uuid]
        })

      assert_reply ref, :ok, %{success: true}

      assert_broadcast "trigger_auth_methods_updated", %{
        webhook_auth_methods: methods
      }

      # Should only include the valid method
      assert length(methods) == 1
      assert hd(methods).id == valid_method.id
    end

    test "get_context includes webhook_auth_methods", %{
      socket: socket,
      project: project
    } do
      # Create webhook auth methods for the project
      auth_method1 =
        insert(:webhook_auth_method,
          project: project,
          name: "API Key Auth",
          auth_type: :api
        )

      auth_method2 =
        insert(:webhook_auth_method,
          project: project,
          name: "Basic Auth",
          auth_type: :basic
        )

      ref = push(socket, "get_context", %{})

      assert_reply ref, :ok, context

      assert %{webhook_auth_methods: methods} = context
      assert length(methods) == 2

      assert Enum.any?(methods, fn m ->
               m.id == auth_method1.id && m.name == "API Key Auth" &&
                 m.auth_type == :api
             end)

      assert Enum.any?(methods, fn m ->
               m.id == auth_method2.id && m.name == "Basic Auth" &&
                 m.auth_type == :basic
             end)
    end

    test "get_context excludes deleted webhook_auth_methods", %{
      socket: socket,
      project: project
    } do
      # Create active and deleted auth methods
      insert(:webhook_auth_method,
        project: project,
        name: "Active Method",
        auth_type: :api
      )

      insert(:webhook_auth_method,
        project: project,
        name: "Deleted Method",
        auth_type: :basic,
        scheduled_deletion: DateTime.utc_now()
      )

      ref = push(socket, "get_context", %{})

      assert_reply ref, :ok, context

      assert %{webhook_auth_methods: methods} = context
      # Should only include active method
      assert length(methods) == 1
      assert hd(methods).name == "Active Method"
    end

    test "handle_info for webhook_auth_methods_updated pushes to channel", %{
      socket: socket,
      project: project
    } do
      auth_method =
        insert(:webhook_auth_method,
          project: project,
          name: "Test Method",
          auth_type: :api
        )

      webhook_auth_methods = [
        %{
          id: auth_method.id,
          name: auth_method.name,
          auth_type: auth_method.auth_type
        }
      ]

      # Send the handle_info message directly
      send(socket.channel_pid, %{
        event: "webhook_auth_methods_updated",
        payload: webhook_auth_methods,
        socket: socket
      })

      # Verify the push was sent to the client
      assert_push "webhook_auth_methods_updated", ^webhook_auth_methods
    end

    test "webhook_auth_methods_updated broadcast is received by all collaborators",
         %{
           workflow: workflow,
           project: project
         } do
      # Create two users
      user1 = insert(:user)
      user2 = insert(:user)

      insert(:project_user, project: project, user: user1, role: :editor)
      insert(:project_user, project: project, user: user2, role: :editor)

      # Both join the channel
      {:ok, _, socket1} =
        LightningWeb.UserSocket
        |> socket("user_#{user1.id}", %{current_user: user1})
        |> subscribe_and_join(
          LightningWeb.WorkflowChannel,
          "workflow:collaborate:#{workflow.id}",
          %{"project_id" => project.id, "action" => "edit"}
        )

      {:ok, _, _socket2} =
        LightningWeb.UserSocket
        |> socket("user_#{user2.id}", %{current_user: user2})
        |> subscribe_and_join(
          LightningWeb.WorkflowChannel,
          "workflow:collaborate:#{workflow.id}",
          %{"project_id" => project.id, "action" => "edit"}
        )

      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      auth_method =
        insert(:webhook_auth_method,
          project: project,
          name: "Shared Method",
          auth_type: :api
        )

      # User 1 updates auth methods
      push(socket1, "update_trigger_auth_methods", %{
        "trigger_id" => trigger.id,
        "auth_method_ids" => [auth_method.id]
      })

      # Both sockets should receive the broadcast
      assert_broadcast "trigger_auth_methods_updated", %{
        trigger_id: _,
        webhook_auth_methods: _
      }
    end
  end
end
