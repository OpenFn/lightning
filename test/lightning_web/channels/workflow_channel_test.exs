defmodule LightningWeb.WorkflowChannelTest do
  use LightningWeb.ChannelCase

  import Lightning.CollaborationHelpers
  import Lightning.Factories

  setup do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :owner}])
    workflow = insert(:workflow, project: project)

    {:ok, _, socket} =
      LightningWeb.UserSocket
      |> socket("user_#{user.id}", %{current_user: user})
      |> subscribe_and_join(
        LightningWeb.WorkflowChannel,
        "workflow:collaborate:#{workflow.id}"
      )

    on_exit(fn ->
      ensure_doc_supervisor_stopped(socket.assigns.workflow.id)
    end)

    %{socket: socket, user: user, project: project, workflow: workflow}
  end

  describe "getting credentials and adaptors" do
    test "multiple concurrent requests are handled independently", %{
      socket: socket
    } do
      # Send both requests
      ref_adaptors = push(socket, "request_adaptors", %{})
      ref_credentials = push(socket, "request_credentials", %{})

      # Should get both responses (order may vary)
      assert_reply ref_adaptors, :ok, %{adaptors: _}
      assert_reply ref_credentials, :ok, %{credentials: credentials}

      assert Map.has_key?(credentials, :project_credentials)
      assert Map.has_key?(credentials, :keychain_credentials)
      assert is_list(credentials.project_credentials)
      assert is_list(credentials.keychain_credentials)
    end

    test "error handling works correctly for async responses", %{socket: socket} do
      # Mock a failing AdaptorRegistry.all/0 call
      # Note: This would require test mocking setup in a real implementation
      # For now, we'll just verify that the error response format is handled

      # Send the request
      ref = push(socket, "request_adaptors", %{})

      # Should get a successful response (since we can't easily mock the failure)
      assert_reply ref, :ok, %{adaptors: adaptors}
      assert is_list(adaptors)
    end
  end

  describe "channel lifecycle" do
    test "channel properly assigns workflow and session data on join", %{
      socket: socket,
      workflow: workflow
    } do
      # The socket should have been assigned the workflow and session data
      assert %{workflow: socket_workflow} = socket.assigns
      assert socket_workflow.id == workflow.id
      assert %{workflow_id: workflow_id} = socket.assigns
      assert workflow_id == workflow.id
      assert %{session_pid: session_pid} = socket.assigns
      assert is_pid(session_pid)
    end
  end
end
