defmodule LightningWeb.AiAssistantChannelTest do
  use LightningWeb.ChannelCase, async: true

  import Lightning.{
    AccountsFixtures,
    JobsFixtures,
    ProjectsFixtures,
    WorkflowsFixtures
  }

  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.ChatSession
  alias LightningWeb.AiAssistantChannel

  setup do
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

      # Verify the session was created
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
      assert length(messages) == 1
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
      assert length(messages) == 1
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
      assert length(messages) == 1

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
end
