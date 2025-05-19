defmodule Lightning.AiAssistant.ChatSessionTest do
  use Lightning.DataCase, async: true

  alias Lightning.AiAssistant.ChatSession

  describe "changeset/2" do
    test "validates required fields" do
      changeset = ChatSession.changeset(%ChatSession{}, %{})
      assert "can't be blank" in errors_on(changeset).title
      assert "can't be blank" in errors_on(changeset).user_id
    end

    test "validates session_type requirements for job_code" do
      user = insert(:user)
      job = insert(:job)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          session_type: "job_code"
        })

      assert "can't be blank" in errors_on(changeset).job_id

      valid_changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          session_type: "job_code",
          job_id: job.id
        })

      assert valid_changeset.valid?
    end

    test "validates session_type requirements for workflow_template" do
      user = insert(:user)
      project = insert(:project)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          session_type: "workflow_template"
        })

      assert "can't be blank" in errors_on(changeset).project_id

      valid_changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          session_type: "workflow_template",
          project_id: project.id
        })

      assert valid_changeset.valid?
    end

    test "validates invalid session_type" do
      user = insert(:user)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          session_type: "invalid_type"
        })

      assert "must be either 'job_code' or 'workflow_template'" in errors_on(
               changeset
             ).session_type
    end

    test "casts and validates messages association" do
      user = insert(:user)
      job = insert(:job)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          session_type: "job_code",
          job_id: job.id,
          messages: [
            %{
              content: "Test message",
              role: :user,
              user: user
            }
          ]
        })

      assert changeset.valid?
      assert length(changeset.changes.messages) == 1
    end

    test "sets default values" do
      user = insert(:user)
      job = insert(:job)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          session_type: "job_code",
          job_id: job.id
        })

      refute Ecto.Changeset.fetch_field!(changeset, :is_public)
      refute Ecto.Changeset.fetch_field!(changeset, :is_deleted)
    end
  end
end
