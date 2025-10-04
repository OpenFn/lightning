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

  describe "join authorization" do
    test "rejects unauthorized users", %{workflow: workflow} do
      unauthorized_user = insert(:user)

      assert {:error, %{reason: "unauthorized"}} =
               LightningWeb.UserSocket
               |> socket("user_#{unauthorized_user.id}", %{
                 current_user: unauthorized_user
               })
               |> subscribe_and_join(
                 LightningWeb.WorkflowChannel,
                 "workflow:collaborate:#{workflow.id}"
               )
    end

    test "accepts authorized users with proper assigns", %{
      socket: socket,
      workflow: workflow
    } do
      assert %{workflow: socket_workflow} = socket.assigns
      assert socket_workflow.id == workflow.id
      assert %{workflow_id: workflow_id} = socket.assigns
      assert workflow_id == workflow.id
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
      project: project
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
  end
end
