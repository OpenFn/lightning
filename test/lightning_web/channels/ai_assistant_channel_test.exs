defmodule LightningWeb.AiAssistantChannelTest do
  use LightningWeb.ChannelCase, async: true

  import Lightning.{
    AccountsFixtures,
    JobsFixtures,
    ProjectsFixtures,
    WorkflowsFixtures
  }

  alias Lightning.AiAssistant
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
end
