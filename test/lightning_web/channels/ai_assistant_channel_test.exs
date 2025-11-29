defmodule LightningWeb.AiAssistantChannelTest do
  use LightningWeb.ChannelCase, async: true
  import Mox

  import Lightning.{
    AccountsFixtures,
    JobsFixtures,
    ProjectsFixtures,
    WorkflowsFixtures
  }

  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.ChatSession
  alias LightningWeb.AiAssistantChannel

  setup :verify_on_exit!

  setup do
    # Mock Apollo configuration
    Mox.stub(Lightning.MockConfig, :apollo, fn key ->
      case key do
        :endpoint -> "http://localhost:3000"
        :ai_assistant_api_key -> "test_api_key"
        :timeout -> 5_000
      end
    end)

    # Mock Tesla HTTP client to prevent real HTTP calls
    Mox.stub(Lightning.Tesla.Mock, :call, fn %{method: :post}, _opts ->
      {:ok,
       %Tesla.Env{
         status: 200,
         body: %{
           "response" => "This is a test AI response.",
           "history" => [
             %{"role" => "user", "content" => "test message"},
             %{"role" => "assistant", "content" => "This is a test AI response."}
           ]
         }
       }}
    end)

    user = user_fixture()
    project = project_fixture(project_users: [%{user_id: user.id}])

    workflow =
      workflow_fixture(project_id: project.id, name: "Test Workflow")

    job =
      job_fixture(
        workflow_id: workflow.id,
        name: "Test Job",
        body: "console.log('test');",
        adaptor: "@openfn/language-common@1.0.0"
      )

    socket =
      LightningWeb.UserSocket
      |> socket("user_#{user.id}", %{current_user: user})

    %{
      socket: socket,
      user: user,
      project: project,
      workflow: workflow,
      job: job
    }
  end

  describe "join ai_assistant:job_code:new with saved job" do
    @tag :capture_log
    test "successfully creates session for existing job", %{
      socket: socket,
      job: job
    } do
      params = %{
        "job_id" => job.id,
        "content" => "Help me with this code"
      }

      assert {:ok, response, _socket} =
               subscribe_and_join(
                 socket,
                 AiAssistantChannel,
                 "ai_assistant:job_code:new",
                 params
               )

      assert %{
               session_id: session_id,
               session_type: "job_code"
             } = response

      assert is_binary(session_id)

      session = AiAssistant.get_session!(session_id)
      assert session.job_id == job.id
      assert session.session_type == "job_code"
    end

    test "requires job_id parameter", %{socket: socket} do
      params = %{"content" => "Help me"}

      assert {:error, %{reason: "job_id required"}} =
               subscribe_and_join(
                 socket,
                 AiAssistantChannel,
                 "ai_assistant:job_code:new",
                 params
               )
    end

    test "requires content parameter", %{socket: socket, job: job} do
      params = %{"job_id" => job.id}

      assert {:error, %{reason: "initial content required"}} =
               subscribe_and_join(
                 socket,
                 AiAssistantChannel,
                 "ai_assistant:job_code:new",
                 params
               )
    end
  end

  describe "join ai_assistant:job_code:new with unsaved job" do
    test "returns error for unsaved job", %{socket: socket} do
      # Generate a UUID for an unsaved job (not in database)
      unsaved_job_id = Ecto.UUID.generate()

      params = %{
        "job_id" => unsaved_job_id,
        "content" => "Help me with this unsaved job"
      }

      assert {:error,
              %{
                reason:
                  "Please save the workflow before using AI Assistant for this job"
              }} =
               subscribe_and_join(
                 socket,
                 AiAssistantChannel,
                 "ai_assistant:job_code:new",
                 params
               )
    end
  end

  describe "join existing session" do
    @tag :capture_log
    test "successfully joins existing job_code session", %{
      socket: socket,
      job: job,
      user: user
    } do
      {:ok, session} =
        AiAssistant.create_session(job, user, "Initial message", [])

      assert {:ok, response, _socket} =
               subscribe_and_join(
                 socket,
                 AiAssistantChannel,
                 "ai_assistant:job_code:#{session.id}",
                 %{}
               )

      assert %{
               session_id: session_id,
               session_type: "job_code",
               messages: messages
             } = response

      assert session_id == session.id
      # Expect 2 messages: user message + AI response (due to mocked HTTP client)
      assert length(messages) == 2
    end
  end

  describe "workflow_template sessions" do
    @tag :capture_log
    test "successfully creates workflow template session", %{
      socket: socket,
      project: project
    } do
      params = %{
        "project_id" => project.id,
        "content" => "Create a workflow for data collection"
      }

      assert {:ok, response, _socket} =
               subscribe_and_join(
                 socket,
                 AiAssistantChannel,
                 "ai_assistant:workflow_template:new",
                 params
               )

      assert %{
               session_id: session_id,
               session_type: "workflow_template",
               messages: messages
             } = response

      assert is_binary(session_id)
      # Expect 2 messages: user message + AI response (due to mocked HTTP client)
      assert length(messages) == 2
    end
  end

  describe "join ai_assistant:workflow_template:new with create mode workflow" do
    @tag :capture_log
    test "successfully creates session for unsaved workflow", %{
      socket: socket,
      project: project
    } do
      # Temporary workflow ID (not in database - create mode)
      temp_workflow_id = Ecto.UUID.generate()

      params = %{
        "project_id" => project.id,
        "workflow_id" => temp_workflow_id,
        "content" => "Help me create a workflow for data imports"
      }

      assert {:ok, response, _socket} =
               subscribe_and_join(
                 socket,
                 AiAssistantChannel,
                 "ai_assistant:workflow_template:new",
                 params
               )

      assert %{
               session_id: session_id,
               session_type: "workflow_template",
               messages: messages
             } = response

      assert is_binary(session_id)
      # Expect 2 messages: user message + AI response (due to mocked HTTP client)
      assert length(messages) == 2

      # Verify the session was created with unsaved_workflow in meta
      session = Repo.get!(ChatSession, session_id)
      assert session.workflow_id == nil
      assert session.project_id == project.id
      assert session.session_type == "workflow_template"
      assert session.meta["unsaved_workflow"]["id"] == temp_workflow_id
      assert session.meta["unsaved_workflow"]["is_new"] == true
    end

    @tag :capture_log
    test "creates session without unsaved_workflow when workflow exists", %{
      socket: socket,
      project: project,
      workflow: workflow
    } do
      params = %{
        "project_id" => project.id,
        "workflow_id" => workflow.id,
        "content" => "Help me improve this workflow"
      }

      assert {:ok, response, _socket} =
               subscribe_and_join(
                 socket,
                 AiAssistantChannel,
                 "ai_assistant:workflow_template:new",
                 params
               )

      assert %{
               session_id: session_id,
               session_type: "workflow_template"
             } = response

      # Verify the session was created with workflow_id (no unsaved_workflow)
      session = Repo.get!(ChatSession, session_id)
      assert session.workflow_id == workflow.id
      assert session.project_id == project.id
      refute Map.has_key?(session.meta, "unsaved_workflow")
    end
  end

  describe "list_sessions for workflow_template" do
    test "filters sessions by workflow_id matching legacy editor behavior", %{
      socket: socket,
      user: user,
      project: project,
      workflow: workflow
    } do
      # Create another workflow in the same project
      workflow2 =
        workflow_fixture(project_id: project.id, name: "Workflow 2")

      # Create sessions for workflow 1
      {:ok, session1} =
        AiAssistant.create_workflow_session(
          project,
          workflow,
          user,
          "Create workflow 1 template"
        )

      # Create session for workflow 2
      {:ok, _session2} =
        AiAssistant.create_workflow_session(
          project,
          workflow2,
          user,
          "Create workflow 2 template"
        )

      # Create session without workflow (unsaved)
      {:ok, _session3} =
        AiAssistant.create_workflow_session(
          project,
          nil,
          user,
          "Create new workflow template"
        )

      # Join channel with workflow 1 session
      {:ok, _, socket} =
        subscribe_and_join(
          socket,
          AiAssistantChannel,
          "ai_assistant:workflow_template:#{session1.id}",
          %{}
        )

      # List sessions - should only get sessions for workflow 1
      ref = push(socket, "list_sessions", %{"offset" => 0, "limit" => 20})

      assert_reply ref, :ok, %{sessions: sessions, pagination: pagination}

      # Should only return sessions for workflow 1
      assert length(sessions) == 1
      assert pagination.total_count == 1
      assert hd(sessions).workflow_name == workflow.name
    end

    test "lists only unsaved workflow sessions when session has no workflow_id",
         %{
           socket: socket,
           user: user,
           project: project,
           workflow: workflow
         } do
      # Create session with workflow
      {:ok, _session1} =
        AiAssistant.create_workflow_session(
          project,
          workflow,
          user,
          "Workflow with ID"
        )

      # Create sessions without workflow (unsaved)
      {:ok, session_unsaved} =
        AiAssistant.create_workflow_session(
          project,
          nil,
          user,
          "New unsaved workflow"
        )

      {:ok, _session_unsaved2} =
        AiAssistant.create_workflow_session(
          project,
          nil,
          user,
          "Another unsaved workflow"
        )

      # Join channel with unsaved workflow session
      {:ok, _, socket} =
        subscribe_and_join(
          socket,
          AiAssistantChannel,
          "ai_assistant:workflow_template:#{session_unsaved.id}",
          %{}
        )

      # List sessions - should only get unsaved sessions (workflow_id = nil)
      ref = push(socket, "list_sessions", %{"offset" => 0, "limit" => 20})

      assert_reply ref, :ok, %{sessions: sessions, pagination: pagination}

      # Should only return sessions without workflow_id
      assert length(sessions) == 2
      assert pagination.total_count == 2
      assert Enum.all?(sessions, &is_nil(&1[:workflow_name]))
    end

    test "handles pagination correctly for workflow-scoped sessions", %{
      socket: socket,
      user: user,
      project: project,
      workflow: workflow
    } do
      # Create 3 sessions for workflow 1
      sessions =
        for i <- 1..3 do
          {:ok, session} =
            AiAssistant.create_workflow_session(
              project,
              workflow,
              user,
              "Template #{i}"
            )

          session
        end

      # Join with first session
      first_session = hd(sessions)

      {:ok, _, socket} =
        subscribe_and_join(
          socket,
          AiAssistantChannel,
          "ai_assistant:workflow_template:#{first_session.id}",
          %{}
        )

      # Request with limit 2
      ref = push(socket, "list_sessions", %{"offset" => 0, "limit" => 2})

      assert_reply ref, :ok, %{sessions: page1_sessions, pagination: pagination1}

      assert length(page1_sessions) == 2
      assert pagination1.total_count == 3
      assert pagination1.has_next_page == true

      # Request next page
      ref2 = push(socket, "list_sessions", %{"offset" => 2, "limit" => 2})

      assert_reply ref2, :ok, %{
        sessions: page2_sessions,
        pagination: pagination2
      }

      assert length(page2_sessions) == 1
      assert pagination2.total_count == 3
      assert pagination2.has_next_page == false
    end
  end

  describe "handle_in new_message" do
    @tag :capture_log
    test "successfully saves and processes user message", %{
      socket: socket,
      job: job,
      user: user
    } do
      {:ok, session} =
        AiAssistant.create_session(job, user, "Initial message", [])

      {:ok, _, socket} =
        subscribe_and_join(
          socket,
          AiAssistantChannel,
          "ai_assistant:job_code:#{session.id}",
          %{}
        )

      ref = push(socket, "new_message", %{"content" => "Help me debug this"})

      assert_reply ref, :ok, %{message: message}
      assert message.content == "Help me debug this"
      assert message.role == "user"
      # Status is "success" due to mocked HTTP client processing immediately
      assert message.status in ["pending", "success"]
    end

    test "rejects empty message", %{socket: socket, job: job, user: user} do
      {:ok, session} =
        AiAssistant.create_session(job, user, "Initial message", [])

      {:ok, _, socket} =
        subscribe_and_join(
          socket,
          AiAssistantChannel,
          "ai_assistant:job_code:#{session.id}",
          %{}
        )

      ref = push(socket, "new_message", %{"content" => "   "})

      assert_reply ref, :error, %{reason: "Message cannot be empty"}
    end

    test "includes code when attach_code is true", %{
      socket: socket,
      job: job,
      user: user
    } do
      {:ok, session} =
        AiAssistant.create_session(job, user, "Initial message", [])

      {:ok, _, socket} =
        subscribe_and_join(
          socket,
          AiAssistantChannel,
          "ai_assistant:job_code:#{session.id}",
          %{}
        )

      ref =
        push(socket, "new_message", %{
          "content" => "Explain this code",
          "attach_code" => true
        })

      assert_reply ref, :ok, %{message: message}
      assert message.content == "Explain this code"
    end
  end

  describe "handle_in mark_disclaimer_read" do
    test "successfully marks disclaimer as read", %{
      socket: socket,
      job: job,
      user: user
    } do
      {:ok, session} =
        AiAssistant.create_session(job, user, "Initial message", [])

      {:ok, _, socket} =
        subscribe_and_join(
          socket,
          AiAssistantChannel,
          "ai_assistant:job_code:#{session.id}",
          %{}
        )

      ref = push(socket, "mark_disclaimer_read", %{})

      assert_reply ref, :ok, %{success: true}

      # Verify user preferences were updated
      updated_user = Lightning.Accounts.get_user!(user.id)
      assert updated_user.preferences["ai_assistant.disclaimer_read_at"] != nil
    end
  end

  describe "handle_in update_context" do
    test "updates job context for job_code session", %{
      socket: socket,
      job: job,
      user: user
    } do
      {:ok, session} =
        AiAssistant.create_session(job, user, "Initial message", [])

      {:ok, _, socket} =
        subscribe_and_join(
          socket,
          AiAssistantChannel,
          "ai_assistant:job_code:#{session.id}",
          %{}
        )

      ref =
        push(socket, "update_context", %{
          "job_body" => "console.log('updated');",
          "job_adaptor" => "@openfn/language-common@2.0.0",
          "job_name" => "Updated Job"
        })

      assert_reply ref, :ok, %{success: true}

      # Verify session meta was updated
      updated_session = AiAssistant.get_session!(session.id)
      runtime_context = updated_session.meta["runtime_context"]
      assert runtime_context["job_body"] == "console.log('updated');"
      assert runtime_context["job_adaptor"] == "@openfn/language-common@2.0.0"
      assert runtime_context["job_name"] == "Updated Job"
      assert runtime_context["updated_at"] != nil
    end

    test "rejects update_context for workflow_template session", %{
      socket: socket,
      project: project,
      user: user
    } do
      {:ok, session} =
        AiAssistant.create_workflow_session(
          project,
          nil,
          user,
          "Create workflow"
        )

      {:ok, _, socket} =
        subscribe_and_join(
          socket,
          AiAssistantChannel,
          "ai_assistant:workflow_template:#{session.id}",
          %{}
        )

      ref =
        push(socket, "update_context", %{
          "job_body" => "console.log('test');"
        })

      assert_reply ref, :error, %{
        reason: "Context updates only supported for job_code sessions"
      }
    end
  end

  describe "authorization" do
    test "rejects join without authenticated user", %{job: job} do
      socket = socket(LightningWeb.UserSocket, "unauthenticated", %{})

      params = %{
        "job_id" => job.id,
        "content" => "Help me"
      }

      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(
                 socket,
                 AiAssistantChannel,
                 "ai_assistant:job_code:new",
                 params
               )
    end

    test "rejects join with invalid topic format", %{socket: socket} do
      assert {:error, %{reason: "invalid topic format"}} =
               subscribe_and_join(
                 socket,
                 AiAssistantChannel,
                 "ai_assistant:invalid_type:123",
                 %{}
               )
    end

    test "rejects join when session type doesn't match", %{
      socket: socket,
      job: job,
      user: user
    } do
      # Create a job_code session
      {:ok, session} =
        AiAssistant.create_session(job, user, "Initial message", [])

      # Try to join it as workflow_template
      assert {:error, %{reason: "session type mismatch"}} =
               subscribe_and_join(
                 socket,
                 AiAssistantChannel,
                 "ai_assistant:workflow_template:#{session.id}",
                 %{}
               )
    end
  end

  describe "handle_in unsaved job with proper metadata" do
    @tag :capture_log
    test "creates session for unsaved job with all metadata", %{
      socket: socket,
      workflow: workflow
    } do
      unsaved_job_id = Ecto.UUID.generate()

      params = %{
        "job_id" => unsaved_job_id,
        "job_name" => "Unsaved Job",
        "job_body" => "console.log('unsaved');",
        "job_adaptor" => "@openfn/language-common@1.0.0",
        "workflow_id" => workflow.id,
        "content" => "Help me with this unsaved job"
      }

      assert {:ok, response, _socket} =
               subscribe_and_join(
                 socket,
                 AiAssistantChannel,
                 "ai_assistant:job_code:new",
                 params
               )

      assert %{session_id: session_id, session_type: "job_code"} = response

      # Verify session has unsaved_job metadata
      session = AiAssistant.get_session!(session_id)
      assert session.job_id == nil
      unsaved_job = session.meta["unsaved_job"]
      assert unsaved_job["id"] == unsaved_job_id
      assert unsaved_job["name"] == "Unsaved Job"
      assert unsaved_job["body"] == "console.log('unsaved');"
      assert unsaved_job["adaptor"] == "@openfn/language-common@1.0.0"
      assert unsaved_job["workflow_id"] == workflow.id
    end
  end

  describe "workflow_template error cases" do
    test "requires project_id parameter", %{socket: socket} do
      params = %{"content" => "Create workflow"}

      assert {:error, %{reason: "project_id required"}} =
               subscribe_and_join(
                 socket,
                 AiAssistantChannel,
                 "ai_assistant:workflow_template:new",
                 params
               )
    end

    test "requires content parameter", %{socket: socket, project: project} do
      params = %{"project_id" => project.id}

      assert {:error, %{reason: "initial content required"}} =
               subscribe_and_join(
                 socket,
                 AiAssistantChannel,
                 "ai_assistant:workflow_template:new",
                 params
               )
    end

    test "returns error for non-existent project", %{socket: socket} do
      fake_project_id = Ecto.UUID.generate()

      params = %{
        "project_id" => fake_project_id,
        "content" => "Create workflow"
      }

      assert {:error, %{reason: "project not found"}} =
               subscribe_and_join(
                 socket,
                 AiAssistantChannel,
                 "ai_assistant:workflow_template:new",
                 params
               )
    end
  end

  describe "list_sessions for job_code" do
    test "lists sessions for a job", %{
      socket: socket,
      user: user,
      job: job
    } do
      # Create multiple sessions for the job
      {:ok, session1} =
        AiAssistant.create_session(job, user, "First session", [])

      {:ok, _session2} =
        AiAssistant.create_session(job, user, "Second session", [])

      # Join with first session
      {:ok, _, socket} =
        subscribe_and_join(
          socket,
          AiAssistantChannel,
          "ai_assistant:job_code:#{session1.id}",
          %{}
        )

      ref = push(socket, "list_sessions", %{"offset" => 0, "limit" => 20})

      assert_reply ref, :ok, %{sessions: sessions, pagination: pagination}

      assert length(sessions) == 2
      assert pagination.total_count == 2
      assert Enum.all?(sessions, &(&1.job_name == job.name))
    end
  end
end
