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

    test "sets default session_type to job_code" do
      user = insert(:user)
      job = insert(:job)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          job_id: job.id
        })

      assert Ecto.Changeset.fetch_field!(changeset, :session_type) == "job_code"
    end

    test "accepts explicit session_type" do
      user = insert(:user)
      project = insert(:project)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          session_type: "workflow_template",
          project_id: project.id
        })

      assert Ecto.Changeset.fetch_field!(changeset, :session_type) ==
               "workflow_template"
    end

    test "validates session_type inclusion with valid values" do
      user = insert(:user)
      job = insert(:job)
      project = insert(:project)

      changeset_job =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Job Code Session",
          user_id: user.id,
          session_type: "job_code",
          job_id: job.id
        })

      assert changeset_job.valid?

      changeset_workflow =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Workflow Template Session",
          user_id: user.id,
          session_type: "workflow_template",
          project_id: project.id
        })

      assert changeset_workflow.valid?
    end

    test "rejects invalid session_type values" do
      user = insert(:user)

      invalid_types = ["invalid", "job", "workflow", "random_string", 123]

      for invalid_type <- invalid_types do
        changeset =
          ChatSession.changeset(%ChatSession{}, %{
            title: "Test Session",
            user_id: user.id,
            session_type: invalid_type
          })

        refute changeset.valid?,
               "Session type #{inspect(invalid_type)} should be invalid"

        errors = errors_on(changeset)

        assert Map.has_key?(errors, :session_type),
               "Expected session_type error for #{inspect(invalid_type)}"

        assert "is invalid" in errors.session_type
      end
    end

    test "handles edge case session_type values" do
      user = insert(:user)

      changeset_empty =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          session_type: ""
        })

      refute changeset_empty.valid?
      errors = errors_on(changeset_empty)
      assert Map.has_key?(errors, :job_id) or Map.has_key?(errors, :session_type)

      changeset_nil =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          session_type: nil
        })

      refute changeset_nil.valid?
      errors = errors_on(changeset_nil)
      assert Map.has_key?(errors, :session_type)

      assert "must be either 'job_code' or 'workflow_template'" in errors.session_type
    end

    test "accepts meta field as map" do
      user = insert(:user)
      job = insert(:job)

      meta_data = %{
        "api_version" => "v2",
        "last_error" => "timeout",
        "retry_count" => 3
      }

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          job_id: job.id,
          meta: meta_data
        })

      assert changeset.valid?
      assert Ecto.Changeset.fetch_field!(changeset, :meta) == meta_data
    end

    test "sets default empty map for meta" do
      user = insert(:user)
      job = insert(:job)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          job_id: job.id
        })

      assert Ecto.Changeset.fetch_field!(changeset, :meta) == %{}
    end

    test "accepts boolean fields" do
      user = insert(:user)
      job = insert(:job)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          job_id: job.id,
          is_public: true,
          is_deleted: true
        })

      assert changeset.valid?
      assert Ecto.Changeset.fetch_field!(changeset, :is_public) == true
      assert Ecto.Changeset.fetch_field!(changeset, :is_deleted) == true
    end

    test "accepts optional workflow_id" do
      user = insert(:user)
      job = insert(:job)
      workflow = insert(:workflow)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          job_id: job.id,
          workflow_id: workflow.id
        })

      assert changeset.valid?
      assert Ecto.Changeset.fetch_field!(changeset, :workflow_id) == workflow.id
    end

    test "workflow_id is optional for job_code sessions" do
      user = insert(:user)
      job = insert(:job)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          session_type: "job_code",
          job_id: job.id
        })

      assert changeset.valid?
      assert Ecto.Changeset.fetch_field!(changeset, :workflow_id) == nil
    end

    test "workflow_id is optional for workflow_template sessions" do
      user = insert(:user)
      project = insert(:project)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          session_type: "workflow_template",
          project_id: project.id
        })

      assert changeset.valid?
      assert Ecto.Changeset.fetch_field!(changeset, :workflow_id) == nil
    end

    test "handles invalid messages in association" do
      user = insert(:user)
      job = insert(:job)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          job_id: job.id,
          messages: [
            %{
              role: :user,
              user: user
            }
          ]
        })

      refute changeset.valid?
      assert %{messages: [%{content: ["can't be blank"]}]} = errors_on(changeset)
    end

    test "handles multiple messages in association" do
      user = insert(:user)
      job = insert(:job)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          job_id: job.id,
          messages: [
            %{
              content: "First message",
              role: :user,
              user: user
            },
            %{
              content: "AI response",
              role: :assistant
            }
          ]
        })

      assert changeset.valid?
      assert length(changeset.changes.messages) == 2
    end

    test "job_code session with project_id is valid" do
      user = insert(:user)
      job = insert(:job)
      project = insert(:project)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          session_type: "job_code",
          job_id: job.id,
          project_id: project.id
        })

      assert changeset.valid?
    end

    test "workflow_template session with job_id is valid" do
      user = insert(:user)
      job = insert(:job)
      project = insert(:project)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          session_type: "workflow_template",
          project_id: project.id,
          job_id: job.id
        })

      assert changeset.valid?
    end

    test "accepts string values for ID fields" do
      user = insert(:user)
      job = insert(:job)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: to_string(user.id),
          job_id: to_string(job.id),
          session_type: "job_code"
        })

      assert changeset.valid?
      assert Ecto.Changeset.fetch_field!(changeset, :user_id) == user.id
      assert Ecto.Changeset.fetch_field!(changeset, :job_id) == job.id
    end
  end

  describe "integration scenarios" do
    test "creates complete job_code session with all fields" do
      user = insert(:user)
      job = insert(:job)
      workflow = insert(:workflow)

      attrs = %{
        title: "Debug payment processing job",
        session_type: "job_code",
        user_id: user.id,
        job_id: job.id,
        workflow_id: workflow.id,
        is_public: false,
        is_deleted: false,
        meta: %{
          "api_version" => "v2",
          "last_error" => "timeout"
        },
        messages: [
          %{
            content: "Help me debug this error",
            role: :user,
            user: user
          },
          %{
            content: "I can help you with that. Let me analyze the code.",
            role: :assistant
          }
        ]
      }

      changeset = ChatSession.changeset(%ChatSession{}, attrs)
      assert changeset.valid?

      assert Ecto.Changeset.fetch_field!(changeset, :title) ==
               "Debug payment processing job"

      assert Ecto.Changeset.fetch_field!(changeset, :session_type) == "job_code"
      assert Ecto.Changeset.fetch_field!(changeset, :user_id) == user.id
      assert Ecto.Changeset.fetch_field!(changeset, :job_id) == job.id
      assert Ecto.Changeset.fetch_field!(changeset, :workflow_id) == workflow.id
      assert Ecto.Changeset.fetch_field!(changeset, :is_public) == false
      assert Ecto.Changeset.fetch_field!(changeset, :is_deleted) == false

      assert Ecto.Changeset.fetch_field!(changeset, :meta) == %{
               "api_version" => "v2",
               "last_error" => "timeout"
             }

      assert length(changeset.changes.messages) == 2
    end

    test "creates complete workflow_template session with all fields" do
      user = insert(:user)
      project = insert(:project)

      attrs = %{
        title: "New data pipeline workflow",
        session_type: "workflow_template",
        user_id: user.id,
        project_id: project.id,
        is_public: true,
        meta: %{
          "template_category" => "data_processing",
          "complexity" => "intermediate"
        }
      }

      changeset = ChatSession.changeset(%ChatSession{}, attrs)
      assert changeset.valid?

      assert Ecto.Changeset.fetch_field!(changeset, :title) ==
               "New data pipeline workflow"

      assert Ecto.Changeset.fetch_field!(changeset, :session_type) ==
               "workflow_template"

      assert Ecto.Changeset.fetch_field!(changeset, :user_id) == user.id
      assert Ecto.Changeset.fetch_field!(changeset, :project_id) == project.id
      assert Ecto.Changeset.fetch_field!(changeset, :job_id) == nil
      assert Ecto.Changeset.fetch_field!(changeset, :is_public) == true
    end

    test "minimal valid job_code session" do
      user = insert(:user)
      job = insert(:job)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Minimal Session",
          user_id: user.id,
          job_id: job.id
        })

      assert changeset.valid?
      assert Ecto.Changeset.fetch_field!(changeset, :session_type) == "job_code"
      assert Ecto.Changeset.fetch_field!(changeset, :is_public) == false
      assert Ecto.Changeset.fetch_field!(changeset, :is_deleted) == false
      assert Ecto.Changeset.fetch_field!(changeset, :meta) == %{}
    end

    test "minimal valid workflow_template session" do
      user = insert(:user)
      project = insert(:project)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Minimal Workflow Session",
          session_type: "workflow_template",
          user_id: user.id,
          project_id: project.id
        })

      assert changeset.valid?
      assert Ecto.Changeset.fetch_field!(changeset, :is_public) == false
      assert Ecto.Changeset.fetch_field!(changeset, :is_deleted) == false
      assert Ecto.Changeset.fetch_field!(changeset, :meta) == %{}
    end
  end

  describe "meta_changeset/2" do
    test "updates only meta field without triggering validations" do
      user = insert(:user)
      session = insert(:chat_session, user: user, job_id: nil, meta: %{})

      # This should succeed even though job_id is nil and no unsaved_job data
      changeset =
        ChatSession.meta_changeset(session, %{
          meta: %{"rag" => %{"test" => "data"}}
        })

      assert changeset.valid?
      assert changeset.changes.meta == %{"rag" => %{"test" => "data"}}
    end

    test "preserves existing job_id when updating meta" do
      user = insert(:user)
      job = insert(:job)

      session =
        insert(:chat_session,
          user: user,
          job_id: job.id,
          meta: %{"foo" => "bar"}
        )

      changeset =
        ChatSession.meta_changeset(session, %{meta: %{"new" => "value"}})

      assert changeset.valid?
      assert changeset.changes.meta == %{"new" => "value"}
      # job_id should remain unchanged
      refute Map.has_key?(changeset.changes, :job_id)
    end

    test "allows updating meta on unsaved job session" do
      user = insert(:user)

      unsaved_job_meta = %{
        "unsaved_job" => %{
          "id" => "temp-123",
          "body" => "console.log('test')",
          "adaptor" => "@openfn/language-common@latest"
        }
      }

      session =
        insert(:chat_session, user: user, job_id: nil, meta: unsaved_job_meta)

      # Update with RAG data that doesn't include unsaved_job
      new_meta = %{"rag" => %{"sources" => ["doc1", "doc2"]}}
      changeset = ChatSession.meta_changeset(session, %{meta: new_meta})

      assert changeset.valid?
      assert changeset.changes.meta == new_meta
    end

    test "does not validate other fields" do
      user = insert(:user)
      session = insert(:chat_session, user: user, job_id: nil, meta: %{})

      # This would fail with regular changeset but succeeds with meta_changeset
      changeset =
        ChatSession.meta_changeset(session, %{meta: %{"key" => "value"}})

      assert changeset.valid?
      # Should only cast meta field
      assert Map.keys(changeset.changes) == [:meta]
    end
  end

  describe "boundary conditions" do
    test "empty meta map is valid" do
      user = insert(:user)
      job = insert(:job)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          job_id: job.id,
          meta: %{}
        })

      assert changeset.valid?
      assert Ecto.Changeset.fetch_field!(changeset, :meta) == %{}
    end

    test "nil values for optional fields" do
      user = insert(:user)
      job = insert(:job)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          job_id: job.id,
          workflow_id: nil
        })

      assert changeset.valid?
      assert Ecto.Changeset.fetch_field!(changeset, :workflow_id) == nil
      assert Ecto.Changeset.fetch_field!(changeset, :meta) == %{}
    end

    test "explicit nil meta uses schema default" do
      user = insert(:user)
      job = insert(:job)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          job_id: job.id,
          meta: nil
        })

      assert changeset.valid?
      assert Ecto.Changeset.fetch_field!(changeset, :meta) == nil
    end

    test "empty messages list is valid" do
      user = insert(:user)
      job = insert(:job)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          job_id: job.id,
          messages: []
        })

      assert changeset.valid?
      assert changeset.changes[:messages] == []
    end
  end
end
