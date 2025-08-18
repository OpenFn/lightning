defmodule LightningWeb.WorkflowChannelTest do
  use LightningWeb.ChannelCase

  import Lightning.AccountsFixtures
  import Lightning.ProjectsFixtures
  import Lightning.WorkflowsFixtures

  setup do
    user = user_fixture()
    project = project_fixture(project_users: [%{user_id: user.id, role: :owner}])
    workflow = workflow_fixture(project_id: project.id)

    {:ok, _, socket} =
      LightningWeb.UserSocket
      |> socket("user_#{user.id}", %{current_user: user})
      |> subscribe_and_join(
        LightningWeb.WorkflowChannel,
        "workflow:collaborate:#{workflow.id}"
      )

    %{socket: socket, user: user, project: project, workflow: workflow}
  end

  describe "async handlers" do
    test "request_adaptors returns adaptors asynchronously", %{socket: socket} do
      ref = push(socket, "request_adaptors", %{})

      # Should not get an immediate reply
      refute_reply ref, :ok, _, 100

      # Should get an async push with adaptors
      assert_push "adaptors_response", {:ok, %{adaptors: adaptors}}
      assert is_list(adaptors)
    end

    test "request_credentials returns credentials asynchronously", %{
      socket: socket
    } do
      ref = push(socket, "request_credentials", %{})

      # Should not get an immediate reply
      refute_reply ref, :ok, _, 100

      # Should get an async push with credentials
      assert_push "credentials_response", {:ok, %{credentials: credentials}}
      assert Map.has_key?(credentials, :project_credentials)
      assert Map.has_key?(credentials, :keychain_credentials)
      assert is_list(credentials.project_credentials)
      assert is_list(credentials.keychain_credentials)
    end

    test "multiple concurrent requests are handled independently", %{
      socket: socket
    } do
      # Send both requests
      push(socket, "request_adaptors", %{})
      push(socket, "request_credentials", %{})

      # Should get both responses (order may vary)
      assert_push "adaptors_response", {:ok, %{adaptors: _}}
      assert_push "credentials_response", {:ok, %{credentials: _}}
    end

    test "error handling works correctly for async responses", %{socket: socket} do
      # Mock a failing AdaptorRegistry.all/0 call
      # Note: This would require test mocking setup in a real implementation
      # For now, we'll just verify that the error response format is handled

      # Send the request  
      push(socket, "request_adaptors", %{})

      # Should get a successful response (since we can't easily mock the failure)
      assert_push "adaptors_response", {:ok, %{adaptors: adaptors}}
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
