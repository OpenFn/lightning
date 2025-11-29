defmodule Lightning.AiAssistant.UnsavedJobTest do
  use Lightning.DataCase, async: true

  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.ChatSession

  import Oban.Testing, only: [with_testing_mode: 2]

  describe "create_session_for_unsaved_job/3" do
    @tag :skip_oban
    test "creates session with unsaved job data in meta" do
      user = insert(:user)
      workflow = insert(:workflow)

      unsaved_job_data = %{
        "id" => Ecto.UUID.generate(),
        "name" => "Unsaved Job",
        "body" => "console.log('test');",
        "adaptor" => "@openfn/language-common@latest",
        "workflow_id" => workflow.id
      }

      meta = %{"unsaved_job" => unsaved_job_data}
      content = "Help me with this job"

      # Disable Oban for this test to avoid AI calls
      with_testing_mode(:manual, fn ->
        assert {:ok, session} =
                 AiAssistant.create_session_for_unsaved_job(user, content, meta)

        assert session.job_id == nil
        assert session.user_id == user.id
        assert session.session_type == "job_code"
        assert session.meta["unsaved_job"] == unsaved_job_data
        assert session.title == "Help me with this job"

        assert length(session.messages) == 1
        message = hd(session.messages)
        assert message.role == :user
        assert message.content == content
      end)
    end

    test "enriches session with job context from meta" do
      user = insert(:user)
      workflow = insert(:workflow)

      unsaved_job_data = %{
        "id" => Ecto.UUID.generate(),
        "name" => "My Job",
        "body" => "fn(state => state);",
        "adaptor" => "@openfn/language-http@latest",
        "workflow_id" => workflow.id
      }

      meta = %{"unsaved_job" => unsaved_job_data}

      with_testing_mode(:manual, fn ->
        {:ok, session} =
          AiAssistant.create_session_for_unsaved_job(
            user,
            "How do I use this?",
            meta
          )

        enriched_session = AiAssistant.enrich_session_with_job_context(session)

        assert enriched_session.expression == "fn(state => state);"
        # AdaptorRegistry.resolve_adaptor returns versioned adaptor
        assert String.starts_with?(
                 enriched_session.adaptor,
                 "@openfn/language-http"
               )
      end)
    end

    test "can save messages to session with unsaved job" do
      user = insert(:user)
      workflow = insert(:workflow)

      unsaved_job_data = %{
        "id" => Ecto.UUID.generate(),
        "name" => "Test Job",
        "body" => "console.log('hi');",
        "adaptor" => "@openfn/language-common@latest",
        "workflow_id" => workflow.id
      }

      meta = %{"unsaved_job" => unsaved_job_data}

      with_testing_mode(:manual, fn ->
        {:ok, session} =
          AiAssistant.create_session_for_unsaved_job(
            user,
            "Initial message",
            meta
          )

        # Won't trigger AI call with manual mode
        {:ok, updated_session} =
          AiAssistant.save_message(
            session,
            %{role: :user, content: "Follow-up question", user: user},
            []
          )

        assert length(updated_session.messages) == 2
      end)
    end
  end

  describe "ChatSession.changeset with unsaved jobs" do
    test "allows nil job_id when unsaved_job data is in meta" do
      user = insert(:user)
      workflow = insert(:workflow)

      unsaved_job_data = %{
        "id" => Ecto.UUID.generate(),
        "name" => "Unsaved Job",
        "body" => "test",
        "adaptor" => "@openfn/language-common@latest",
        "workflow_id" => workflow.id
      }

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          session_type: "job_code",
          meta: %{"unsaved_job" => unsaved_job_data}
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :job_id) == nil
    end

    test "requires job_id when no unsaved_job data provided" do
      user = insert(:user)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          session_type: "job_code"
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).job_id
    end

    test "allows both job_id and unsaved_job data" do
      user = insert(:user)
      job = insert(:job)
      workflow = insert(:workflow)

      unsaved_job_data = %{
        "id" => Ecto.UUID.generate(),
        "name" => "Unsaved Job",
        "body" => "test",
        "adaptor" => "@openfn/language-common@latest",
        "workflow_id" => workflow.id
      }

      changeset =
        ChatSession.changeset(%ChatSession{}, %{
          title: "Test Session",
          user_id: user.id,
          session_type: "job_code",
          job_id: job.id,
          meta: %{"unsaved_job" => unsaved_job_data}
        })

      assert changeset.valid?
    end
  end

  describe "enrich_session_with_job_context/1" do
    test "uses unsaved_job data when job_id is nil" do
      user = insert(:user)
      workflow = insert(:workflow)

      unsaved_job_data = %{
        "id" => Ecto.UUID.generate(),
        "name" => "Unsaved",
        "body" => "fn(s => s);",
        "adaptor" => "@openfn/language-http@latest",
        "workflow_id" => workflow.id
      }

      meta = %{"unsaved_job" => unsaved_job_data}

      with_testing_mode(:manual, fn ->
        {:ok, session} =
          AiAssistant.create_session_for_unsaved_job(
            user,
            "Help",
            meta
          )

        enriched = AiAssistant.enrich_session_with_job_context(session)

        assert enriched.expression == "fn(s => s);"
        assert String.starts_with?(enriched.adaptor, "@openfn/language-http")
      end)
    end

    test "uses database job when job_id exists and no unsaved_job in meta" do
      user = insert(:user)

      job =
        insert(:job, body: "db_code", adaptor: "@openfn/language-http@1.0")

      with_testing_mode(:manual, fn ->
        {:ok, session} =
          AiAssistant.create_session(job, user, "Help with this", [])

        enriched = AiAssistant.enrich_session_with_job_context(session)

        assert enriched.expression == "db_code"
        assert String.starts_with?(enriched.adaptor, "@openfn/language-http")
      end)
    end

    test "prefers unsaved_job data over database job when both exist" do
      user = insert(:user)

      job =
        insert(:job,
          body: "saved_code",
          adaptor: "@openfn/language-http@1.0"
        )

      workflow = insert(:workflow)

      unsaved_job_data = %{
        "id" => Ecto.UUID.generate(),
        "name" => "Unsaved",
        "body" => "unsaved_code",
        "adaptor" => "@openfn/language-common@latest",
        "workflow_id" => workflow.id
      }

      session_attrs = %{
        job_id: job.id,
        user_id: user.id,
        title: "Test",
        session_type: "job_code",
        meta: %{"unsaved_job" => unsaved_job_data}
      }

      {:ok, session} =
        %ChatSession{}
        |> ChatSession.changeset(session_attrs)
        |> Repo.insert()

      session = Repo.preload(session, :messages)

      # Our implementation checks unsaved_job first
      enriched = AiAssistant.enrich_session_with_job_context(session)

      assert enriched.expression == "unsaved_code"
      assert String.starts_with?(enriched.adaptor, "@openfn/language-common")
    end
  end

  describe "cleanup_unsaved_job_sessions/1" do
    test "cleans up sessions when workflow is saved with matching jobs" do
      user = insert(:user)
      workflow = insert(:workflow)

      # Create some jobs with specific UUIDs (simulating Y.Doc IDs)
      job1_id = Ecto.UUID.generate()
      job2_id = Ecto.UUID.generate()
      job3_id = Ecto.UUID.generate()

      unsaved_job1_data = %{
        "id" => job1_id,
        "name" => "Job 1",
        "body" => "code1",
        "adaptor" => "@openfn/language-common@latest",
        "workflow_id" => workflow.id
      }

      unsaved_job2_data = %{
        "id" => job2_id,
        "name" => "Job 2",
        "body" => "code2",
        "adaptor" => "@openfn/language-common@latest",
        "workflow_id" => workflow.id
      }

      # This one won't get cleaned up (different workflow)
      other_workflow = insert(:workflow)

      unsaved_job3_data = %{
        "id" => job3_id,
        "name" => "Job 3",
        "body" => "code3",
        "adaptor" => "@openfn/language-common@latest",
        "workflow_id" => other_workflow.id
      }

      {:ok, session1} =
        %ChatSession{}
        |> ChatSession.changeset(%{
          user_id: user.id,
          title: "Session 1",
          session_type: "job_code",
          job_id: nil,
          meta: %{"unsaved_job" => unsaved_job1_data}
        })
        |> Repo.insert()

      {:ok, session2} =
        %ChatSession{}
        |> ChatSession.changeset(%{
          user_id: user.id,
          title: "Session 2",
          session_type: "job_code",
          job_id: nil,
          meta: %{"unsaved_job" => unsaved_job2_data}
        })
        |> Repo.insert()

      {:ok, session3} =
        %ChatSession{}
        |> ChatSession.changeset(%{
          user_id: user.id,
          title: "Session 3",
          session_type: "job_code",
          job_id: nil,
          meta: %{"unsaved_job" => unsaved_job3_data}
        })
        |> Repo.insert()

      # Now "save" the workflow by creating jobs with the same IDs
      job1 = insert(:job, id: job1_id, workflow: workflow, name: "Job 1")
      job2 = insert(:job, id: job2_id, workflow: workflow, name: "Job 2")

      workflow = Repo.preload(workflow, :jobs, force: true)

      assert {:ok, 2} = AiAssistant.cleanup_unsaved_job_sessions(workflow)

      updated_session1 = Repo.reload(session1)
      assert updated_session1.job_id == job1.id
      assert updated_session1.meta["unsaved_job"] == nil

      updated_session2 = Repo.reload(session2)
      assert updated_session2.job_id == job2.id
      assert updated_session2.meta["unsaved_job"] == nil

      # Check that session3 was NOT updated (different workflow)
      updated_session3 = Repo.reload(session3)
      assert updated_session3.job_id == nil
      assert updated_session3.meta["unsaved_job"] == unsaved_job3_data
    end

    test "returns 0 when workflow has no jobs" do
      workflow = insert(:workflow)
      assert {:ok, 0} = AiAssistant.cleanup_unsaved_job_sessions(workflow)
    end

    test "returns 0 when no sessions match" do
      workflow = insert(:workflow)
      _job = insert(:job, workflow: workflow)

      workflow = Repo.preload(workflow, :jobs, force: true)

      assert {:ok, 0} = AiAssistant.cleanup_unsaved_job_sessions(workflow)
    end

    test "only updates sessions with job_id = nil" do
      user = insert(:user)
      workflow = insert(:workflow)

      job_id = Ecto.UUID.generate()

      unsaved_job_data = %{
        "id" => job_id,
        "name" => "Job",
        "body" => "code",
        "adaptor" => "@openfn/language-common@latest",
        "workflow_id" => workflow.id
      }

      existing_job = insert(:job, workflow: workflow)

      {:ok, session_with_job_id} =
        %ChatSession{}
        |> ChatSession.changeset(%{
          user_id: user.id,
          title: "Already Linked",
          session_type: "job_code",
          job_id: existing_job.id,
          meta: %{"unsaved_job" => unsaved_job_data}
        })
        |> Repo.insert()

      _job = insert(:job, id: job_id, workflow: workflow)
      workflow = Repo.preload(workflow, :jobs, force: true)

      assert {:ok, 0} = AiAssistant.cleanup_unsaved_job_sessions(workflow)

      updated = Repo.reload(session_with_job_id)
      assert updated.job_id == existing_job.id
      assert updated.meta["unsaved_job"] == unsaved_job_data
    end
  end
end
