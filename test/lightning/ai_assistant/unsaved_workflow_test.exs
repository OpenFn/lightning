defmodule Lightning.AiAssistant.UnsavedWorkflowTest do
  use Lightning.DataCase, async: true

  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.ChatSession

  import Oban.Testing, only: [with_testing_mode: 2]

  describe "create_workflow_session/5 with create mode workflow" do
    @tag :skip_oban
    test "creates session with unsaved workflow data in meta" do
      user = insert(:user)
      project = insert(:project)

      # Temporary workflow ID (not in database - create mode)
      temp_workflow_id = Ecto.UUID.generate()

      content = "Help me create a workflow"

      # Meta includes unsaved_workflow for create mode workflows
      meta = %{
        "unsaved_workflow" => %{
          "id" => temp_workflow_id,
          "is_new" => true
        }
      }

      # Disable Oban for this test to avoid AI calls
      with_testing_mode(:manual, fn ->
        assert {:ok, session} =
                 AiAssistant.create_workflow_session(
                   project,
                   nil,
                   user,
                   content,
                   meta: meta
                 )

        assert session.workflow_id == nil
        assert session.project_id == project.id
        assert session.user_id == user.id
        assert session.session_type == "workflow_template"
        assert session.meta["unsaved_workflow"]["id"] == temp_workflow_id
        assert session.meta["unsaved_workflow"]["is_new"] == true
        assert session.title == "Help me create a workflow"

        # Should have one user message
        assert length(session.messages) == 1
        message = hd(session.messages)
        assert message.role == :user
        assert message.content == content
      end)
    end

    @tag :skip_oban
    test "creates session without unsaved_workflow when workflow exists in DB" do
      user = insert(:user)
      project = insert(:project)
      workflow = insert(:workflow, project: project)

      content = "Help me with this workflow"

      # Disable Oban for this test to avoid AI calls
      with_testing_mode(:manual, fn ->
        assert {:ok, session} =
                 AiAssistant.create_workflow_session(
                   project,
                   workflow,
                   user,
                   content
                 )

        assert session.workflow_id == workflow.id
        assert session.project_id == project.id
        assert session.user_id == user.id
        assert session.session_type == "workflow_template"
        refute Map.has_key?(session.meta, "unsaved_workflow")

        # Should have one user message
        assert length(session.messages) == 1
      end)
    end
  end

  describe "cleanup_unsaved_workflow_sessions/1" do
    @tag :skip_oban
    test "updates sessions when workflow is saved" do
      user = insert(:user)
      project = insert(:project)

      # Create a temporary workflow ID (as in create mode)
      temp_workflow_id = Ecto.UUID.generate()

      # Create sessions with unsaved workflow data
      with_testing_mode(:manual, fn ->
        {:ok, session1} =
          AiAssistant.create_workflow_session(
            project,
            nil,
            user,
            "Create a data import workflow",
            meta: %{
              "unsaved_workflow" => %{
                "id" => temp_workflow_id,
                "is_new" => true
              }
            }
          )

        {:ok, session2} =
          AiAssistant.create_workflow_session(
            project,
            nil,
            user,
            "Make it handle errors",
            meta: %{
              "unsaved_workflow" => %{
                "id" => temp_workflow_id,
                "is_new" => true
              }
            }
          )

        # Verify sessions are created correctly
        assert session1.workflow_id == nil
        assert session2.workflow_id == nil
        assert session1.meta["unsaved_workflow"]["id"] == temp_workflow_id
        assert session2.meta["unsaved_workflow"]["id"] == temp_workflow_id

        # Now "save" the workflow - create it with the temporary ID
        workflow =
          insert(:workflow,
            id: temp_workflow_id,
            project: project,
            name: "My Workflow"
          )

        # Cleanup unsaved workflow sessions
        assert {:ok, 2} = AiAssistant.cleanup_unsaved_workflow_sessions(workflow)

        # Reload sessions from database
        session1_updated = Repo.get!(ChatSession, session1.id)
        session2_updated = Repo.get!(ChatSession, session2.id)

        # Verify sessions now have workflow_id and no unsaved_workflow meta
        assert session1_updated.workflow_id == workflow.id
        assert session2_updated.workflow_id == workflow.id
        refute Map.has_key?(session1_updated.meta, "unsaved_workflow")
        refute Map.has_key?(session2_updated.meta, "unsaved_workflow")
      end)
    end

    @tag :skip_oban
    test "returns 0 when no matching sessions exist" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)

      assert {:ok, 0} = AiAssistant.cleanup_unsaved_workflow_sessions(workflow)
    end

    @tag :skip_oban
    test "only updates sessions for the specific workflow" do
      user = insert(:user)
      project = insert(:project)

      # Create two temporary workflow IDs
      temp_workflow_id_1 = Ecto.UUID.generate()
      temp_workflow_id_2 = Ecto.UUID.generate()

      with_testing_mode(:manual, fn ->
        # Create session for first workflow
        {:ok, session1} =
          AiAssistant.create_workflow_session(
            project,
            nil,
            user,
            "First workflow",
            meta: %{
              "unsaved_workflow" => %{
                "id" => temp_workflow_id_1,
                "is_new" => true
              }
            }
          )

        # Create session for second workflow
        {:ok, session2} =
          AiAssistant.create_workflow_session(
            project,
            nil,
            user,
            "Second workflow",
            meta: %{
              "unsaved_workflow" => %{
                "id" => temp_workflow_id_2,
                "is_new" => true
              }
            }
          )

        # Save only the first workflow
        workflow1 =
          insert(:workflow,
            id: temp_workflow_id_1,
            project: project,
            name: "First Workflow"
          )

        # Cleanup should only update session1
        assert {:ok, 1} =
                 AiAssistant.cleanup_unsaved_workflow_sessions(workflow1)

        # Check session1 is updated
        session1_updated = Repo.get!(ChatSession, session1.id)
        assert session1_updated.workflow_id == workflow1.id
        refute Map.has_key?(session1_updated.meta, "unsaved_workflow")

        # Check session2 is unchanged
        session2_unchanged = Repo.get!(ChatSession, session2.id)
        assert session2_unchanged.workflow_id == nil

        assert session2_unchanged.meta["unsaved_workflow"]["id"] ==
                 temp_workflow_id_2
      end)
    end

    @tag :skip_oban
    test "does not update sessions that already have workflow_id" do
      user = insert(:user)
      project = insert(:project)
      workflow = insert(:workflow, project: project)

      with_testing_mode(:manual, fn ->
        # Create session with existing workflow
        {:ok, session} =
          AiAssistant.create_workflow_session(
            project,
            workflow,
            user,
            "Help with existing workflow"
          )

        assert session.workflow_id == workflow.id

        # Cleanup should not affect this session
        assert {:ok, 0} = AiAssistant.cleanup_unsaved_workflow_sessions(workflow)

        # Session should remain unchanged
        session_unchanged = Repo.get!(ChatSession, session.id)
        assert session_unchanged.workflow_id == workflow.id
      end)
    end
  end
end
