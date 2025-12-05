defmodule LightningWeb.Channels.AiAssistantJSONTest do
  use Lightning.DataCase, async: true

  alias LightningWeb.Channels.AiAssistantJSON

  import Lightning.Factories

  describe "format_session/1" do
    test "formats job_code session with preloaded job and workflow" do
      project = insert(:project)
      workflow = insert(:workflow, project: project, name: "Test Workflow")
      job = insert(:job, workflow: workflow, name: "Test Job")

      session =
        insert(:chat_session,
          session_type: "job_code",
          title: "Job Session",
          job: job,
          meta: %{}
        )
        |> Repo.preload(job: :workflow)

      result = AiAssistantJSON.format_session(session)

      assert result.id == session.id
      assert result.title == "Job Session"
      assert result.session_type == "job_code"
      assert result.job_name == "Test Job"
      assert result.workflow_name == "Test Workflow"
      refute Map.has_key?(result, :is_unsaved)
    end

    test "formats job_code session with unsaved job" do
      project = insert(:project)
      workflow = insert(:workflow, project: project, name: "Test Workflow")
      unsaved_job_id = Ecto.UUID.generate()

      session =
        insert(:chat_session,
          session_type: "job_code",
          title: "Unsaved Job Session",
          job: nil,
          workflow_id: workflow.id,
          meta: %{
            "unsaved_job" => %{
              "id" => unsaved_job_id,
              "name" => "Unsaved Job",
              "workflow_id" => workflow.id
            }
          }
        )
        |> Repo.preload(:workflow)

      result = AiAssistantJSON.format_session(session)

      assert result.id == session.id
      assert result.title == "Unsaved Job Session"
      assert result.session_type == "job_code"
      assert result.job_name == "Unsaved Job"
      assert result.workflow_name == "Test Workflow"
      assert result.is_unsaved == true
    end

    test "formats job_code session with deleted job" do
      # Create a session, then simulate a deleted job by setting associations to nil
      project = insert(:project)
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)

      session =
        insert(:chat_session,
          session_type: "job_code",
          title: "Deleted Job Session",
          job: job,
          meta: %{}
        )

      # Simulate job being deleted - session still has job_id but preload returns nil
      session_with_deleted_job = %{session | job: nil}

      result = AiAssistantJSON.format_session(session_with_deleted_job)

      assert result.id == session.id
      assert result.job_name == "[Deleted Job]"
      assert result.workflow_name == nil
    end

    test "formats job_code session with deleted workflow" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow, name: "Orphaned Job")

      session =
        insert(:chat_session,
          session_type: "job_code",
          title: "Orphaned Job Session",
          job: job,
          meta: %{}
        )
        |> Repo.preload(job: :workflow)

      # Simulate workflow being deleted - job exists but workflow is nil
      job_without_workflow = %{session.job | workflow: nil}
      session_with_orphaned_job = %{session | job: job_without_workflow}

      result = AiAssistantJSON.format_session(session_with_orphaned_job)

      assert result.job_name == "Orphaned Job"
      assert result.workflow_name == nil
    end

    test "formats workflow_template session with preloaded project and workflow" do
      project = insert(:project, name: "Test Project")
      workflow = insert(:workflow, project: project, name: "Test Workflow")

      session =
        insert(:chat_session,
          session_type: "workflow_template",
          title: "Template Session",
          project: project,
          workflow_id: workflow.id,
          job: nil,
          meta: %{}
        )
        |> Repo.preload([:project, :workflow])

      result = AiAssistantJSON.format_session(session)

      assert result.id == session.id
      assert result.title == "Template Session"
      assert result.session_type == "workflow_template"
      assert result.project_name == "Test Project"
      assert result.workflow_name == "Test Workflow"
    end

    test "formats workflow_template session without workflow" do
      project = insert(:project, name: "Test Project")

      session =
        insert(:chat_session,
          session_type: "workflow_template",
          title: "New Workflow Session",
          project: project,
          workflow_id: nil,
          job: nil,
          meta: %{}
        )
        |> Repo.preload([:project, :workflow])

      result = AiAssistantJSON.format_session(session)

      assert result.project_name == "Test Project"
      assert result.workflow_name == nil
    end

    test "includes message_count" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)

      session =
        insert(:chat_session, session_type: "job_code", job: job, meta: %{})
        |> Repo.preload(job: :workflow)

      # Manually set message_count (normally set by list_sessions query)
      session_with_count = Map.put(session, :message_count, 5)

      result = AiAssistantJSON.format_session(session_with_count)

      assert result.message_count == 5
    end

    test "defaults message_count to 0 when nil" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)

      session =
        insert(:chat_session, session_type: "job_code", job: job, meta: %{})
        |> Repo.preload(job: :workflow)
        |> Map.put(:message_count, nil)

      result = AiAssistantJSON.format_session(session)

      assert result.message_count == 0
    end
  end

  describe "format_sessions/1" do
    test "formats multiple sessions" do
      project = insert(:project)
      workflow = insert(:workflow, project: project, name: "Workflow")
      job = insert(:job, workflow: workflow, name: "Job")

      session1 =
        insert(:chat_session,
          session_type: "job_code",
          title: "Session 1",
          job: job,
          meta: %{}
        )
        |> Repo.preload(job: :workflow)

      session2 =
        insert(:chat_session,
          session_type: "workflow_template",
          title: "Session 2",
          project: project,
          job: nil,
          meta: %{}
        )
        |> Repo.preload([:project, :workflow])

      results = AiAssistantJSON.format_sessions([session1, session2])

      assert length(results) == 2
      assert Enum.at(results, 0).title == "Session 1"
      assert Enum.at(results, 1).title == "Session 2"
    end

    test "returns empty list for empty input" do
      assert AiAssistantJSON.format_sessions([]) == []
    end
  end
end
