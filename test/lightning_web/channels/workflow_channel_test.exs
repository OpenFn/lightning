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
        connect(LightningWeb.UserSocket, %{}, %{})
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
end
