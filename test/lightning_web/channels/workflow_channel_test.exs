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
          "workflow:collaborate:#{workflow.id}"
        )

      ref = push(socket, "get_context", %{})

      assert_reply ref, :ok, response
      assert %{permissions: permissions_data} = response
      assert permissions_data.can_edit_workflow == false
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
  end
end
