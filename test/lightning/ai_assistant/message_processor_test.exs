defmodule Lightning.AiAssistant.MessageProcessorTest do
  use Lightning.DataCase, async: true

  @moduletag :capture_log

  import Mox
  import Lightning.Factories

  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.MessageProcessor

  # Note: Integration tests for I/O data scrubbing are tested at lower levels:
  #
  # - test/lightning_web/channels/ai_assistant_channel_test.exs
  #   Tests that attach_io_data and step_id are extracted from params and stored in session meta
  #
  # - test/lightning/ai_assistant/ai_assistant_test.exs
  #   Tests that input and output options are included in the Apollo context
  #
  # The message processor's fetch_and_scrub_io_data/1 logic in
  # lib/lightning/ai_assistant/message_processor.ex is verified through these lower-level tests.
  # Full end-to-end integration testing of dataclip persistence is challenging in the test
  # environment due to test database constraints with map-type columns.

  setup :verify_on_exit!

  setup do
    Mox.stub(Lightning.MockConfig, :apollo, fn key ->
      case key do
        :endpoint -> "http://localhost:3000"
        :ai_assistant_api_key -> "test_api_key"
        :timeout -> 5_000
        :streaming_timeout -> 120_000
      end
    end)

    Mox.stub(
      Lightning.Tesla.Mock,
      :call,
      Lightning.AiAssistantHelpers.streaming_or_sync_response(%{
        "response" => "AI response",
        "history" => [
          %{"role" => "user", "content" => "test"},
          %{"role" => "assistant", "content" => "AI response"}
        ]
      })
    )

    Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn _, _ ->
      :ok
    end)

    Mox.stub(
      Lightning.Extensions.MockUsageLimiter,
      :increment_ai_usage,
      fn _, _ -> Ecto.Multi.new() end
    )

    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :owner}])
    [user: user, project: project]
  end

  setup do
    Process.put(:oban_testing, :manual)
    :ok
  end

  describe "update_session_with_job_context/2" do
    test "sets session.job_id from message and routes to job chat processing", %{
      user: user,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)

      # workflow_template session with no job_id — the session alone is not a job chat
      session =
        insert(:chat_session,
          user: user,
          session_type: "workflow_template",
          project: project,
          workflow: workflow,
          job_id: nil,
          meta: %{}
        )

      # User message carries job_id (e.g. sent while focused on a saved job)
      {:ok, updated_session} =
        AiAssistant.save_message(
          session,
          %{role: :user, content: "help with this job", user: user, job: job},
          []
        )

      user_message = Enum.find(updated_session.messages, &(&1.role == :user))
      assert user_message.job_id == job.id

      # update_session_with_job_context overwrites session.job_id with
      # message.job_id, so job_chat? returns true and process_job_message runs
      assert :ok =
               perform_job(MessageProcessor, %{"message_id" => user_message.id})

      reloaded = AiAssistant.get_session!(session.id)
      assistant_message = Enum.find(reloaded.messages, &(&1.role == :assistant))

      # process_job_message enriches the session with the job and saves the
      # assistant reply with job_id set via maybe_put_job_id_from_session
      assert assistant_message != nil
      assert assistant_message.job_id == job.id
    end

    test "copies unsaved_job from message meta into session meta and routes to job chat processing",
         %{user: user, project: project} do
      unsaved_job_id = Ecto.UUID.generate()
      workflow = insert(:workflow, project: project)

      # workflow_template session — no job in DB, no job_id on session
      session =
        insert(:chat_session,
          user: user,
          session_type: "workflow_template",
          project: project,
          workflow: workflow,
          job_id: nil,
          meta: %{}
        )

      # User message carries unsaved_job data in meta (set by handle_unsaved_job_message)
      {:ok, updated_session} =
        AiAssistant.save_message(
          session,
          %{
            role: :user,
            content: "explain this code",
            user: user,
            meta: %{
              "unsaved_job" => %{
                "id" => unsaved_job_id,
                "name" => "My Unsaved Job",
                "body" => "fn(state => state)",
                "adaptor" => "@openfn/language-common@latest"
              }
            }
          },
          []
        )

      user_message = Enum.find(updated_session.messages, &(&1.role == :user))
      assert user_message.meta["unsaved_job"]["id"] == unsaved_job_id

      # update_session_with_job_context copies meta["unsaved_job"] from the
      # message into session.meta, causing job_chat? to return true
      assert :ok =
               perform_job(MessageProcessor, %{"message_id" => user_message.id})

      reloaded = AiAssistant.get_session!(session.id)
      assistant_message = Enum.find(reloaded.messages, &(&1.role == :assistant))

      # process_job_message runs; maybe_put_unsaved_job_meta tags the assistant
      # reply with the unsaved job id
      assert assistant_message != nil
      assert assistant_message.meta["from_unsaved_job"] == unsaved_job_id
    end

    test "leaves session unchanged and routes to workflow chat processing when message has no job context",
         %{user: user, project: project} do
      workflow = insert(:workflow, project: project)

      session =
        insert(:chat_session,
          user: user,
          session_type: "workflow_template",
          project: project,
          workflow: workflow,
          job_id: nil,
          meta: %{}
        )

      # Plain workflow message — no job_id, no unsaved_job in meta
      {:ok, updated_session} =
        AiAssistant.save_message(
          session,
          %{role: :user, content: "generate a workflow for me", user: user},
          []
        )

      user_message = Enum.find(updated_session.messages, &(&1.role == :user))
      assert is_nil(user_message.job_id)

      # update_session_with_job_context returns the session unchanged, so
      # job_chat? is false and process_workflow_message runs
      assert :ok =
               perform_job(MessageProcessor, %{"message_id" => user_message.id})

      reloaded = AiAssistant.get_session!(session.id)
      assistant_message = Enum.find(reloaded.messages, &(&1.role == :assistant))

      assert assistant_message != nil
      assert is_nil(assistant_message.job_id)
      refute Map.has_key?(assistant_message.meta || %{}, "from_unsaved_job")
    end

    test "processes message successfully when follow_run_id is in message.meta",
         %{
           user: user,
           project: project
         } do
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)

      # Create a run for the job
      work_order = insert(:workorder, workflow: workflow)

      run =
        insert(:run,
          work_order: work_order,
          dataclip: build(:dataclip),
          starting_job: job
        )

      # Create session without follow_run_id (user hasn't selected a run yet)
      session =
        insert(:chat_session,
          user: user,
          session_type: "job_code",
          project: project,
          job_id: job.id,
          meta: %{}
        )

      # User later selects a run mid-session, sending follow_run_id in message params
      {:ok, updated_session} =
        AiAssistant.save_message(
          session,
          %{
            role: :user,
            content: "help me debug these logs",
            user: user,
            job: job,
            meta: %{"follow_run_id" => run.id}
          },
          []
        )

      user_message = Enum.find(updated_session.messages, &(&1.role == :user))
      assert user_message.meta["follow_run_id"] == run.id

      # Process the message - update_session_with_job_context should use
      # follow_run_id from message.meta for enrichment
      assert :ok =
               perform_job(MessageProcessor, %{"message_id" => user_message.id})

      reloaded = AiAssistant.get_session!(session.id)
      assistant_message = Enum.find(reloaded.messages, &(&1.role == :assistant))

      # Verify assistant message was created successfully (proving enrichment worked)
      assert assistant_message != nil
      assert assistant_message.job_id == job.id
    end
  end

  describe "global chat routing" do
    test "dispatches to global chat when use_global_assistant is true", %{
      user: user,
      project: project
    } do
      workflow = insert(:workflow, project: project)

      session =
        insert(:chat_session,
          user: user,
          session_type: "workflow_template",
          project: project,
          workflow: workflow,
          job_id: nil,
          meta: %{
            "message_options" => %{
              "use_global_assistant" => true,
              "page" => "/projects/p1/workflows/w1"
            }
          }
        )

      {:ok, updated_session} =
        AiAssistant.save_message(
          session,
          %{
            role: :user,
            content: "help with my workflow",
            user: user,
            code: "workflow:\n  name: test"
          },
          meta: %{
            "message_options" => %{
              "use_global_assistant" => true,
              "page" => "/projects/p1/workflows/w1"
            }
          }
        )

      user_message = Enum.find(updated_session.messages, &(&1.role == :user))

      # Stub the Tesla mock to verify it hits the global_chat endpoint
      Mox.expect(Lightning.Tesla.Mock, :call, fn %{url: url}, _opts ->
        assert url =~ "/services/global_chat/stream"

        body =
          Jason.encode!(%{
            "response" => "Global response",
            "attachments" => [],
            "usage" => %{}
          })

        {:ok,
         %Tesla.Env{
           status: 200,
           headers: [{"content-type", "text/event-stream"}],
           body: "event: complete\ndata: #{body}\n\n"
         }}
      end)

      assert :ok =
               perform_job(MessageProcessor, %{
                 "message_id" => user_message.id
               })

      reloaded = AiAssistant.get_session!(session.id)
      assistant_msg = Enum.find(reloaded.messages, &(&1.role == :assistant))
      assert assistant_msg != nil
      assert assistant_msg.content == "Global response"
    end

    test "dispatches to workflow chat when use_global_assistant is not set", %{
      user: user,
      project: project
    } do
      workflow = insert(:workflow, project: project)

      session =
        insert(:chat_session,
          user: user,
          session_type: "workflow_template",
          project: project,
          workflow: workflow,
          job_id: nil,
          meta: %{}
        )

      {:ok, updated_session} =
        AiAssistant.save_message(
          session,
          %{role: :user, content: "generate a workflow", user: user},
          []
        )

      user_message = Enum.find(updated_session.messages, &(&1.role == :user))

      # Stub to verify it hits the workflow_chat endpoint (not global_chat)
      Mox.expect(Lightning.Tesla.Mock, :call, fn %{url: url}, _opts ->
        assert url =~ "/services/workflow_chat/stream"

        body =
          Jason.encode!(%{
            "response" => "Workflow response",
            "response_yaml" => "workflow:\n  name: new",
            "usage" => %{}
          })

        {:ok,
         %Tesla.Env{
           status: 200,
           headers: [{"content-type", "text/event-stream"}],
           body: "event: complete\ndata: #{body}\n\n"
         }}
      end)

      assert :ok =
               perform_job(MessageProcessor, %{
                 "message_id" => user_message.id
               })

      reloaded = AiAssistant.get_session!(session.id)
      assistant_msg = Enum.find(reloaded.messages, &(&1.role == :assistant))
      assert assistant_msg != nil
      assert assistant_msg.content == "Workflow response"
    end
  end

  describe "fetch_and_scrub_io_data/1 via process_job_message/2" do
    test "attaching your OWN step egresses its scrubbed input/output to Apollo",
         %{user: user, project: project} do
      %{job: job, step: step} = step_in_run(project)

      user_message = io_attach_message(user, project, job, step.id)

      respond = apollo_streaming_reply()

      # This `expect` takes precedence over the setup `Mox.stub` for the first
      # (and only) POST this path makes. The scrubbed IO rides in "context".
      Mox.expect(Lightning.Tesla.Mock, :call, fn env, opts ->
        assert env.url =~ "/services/job_chat/stream"

        context = Jason.decode!(env.body)["context"]

        # Scrubber.scrub_values/1 preserves keys/shape, reduces values to their
        # type: integers -> "number", strings -> "string", etc.
        assert context["input"] == %{"a" => "number"}
        assert context["output"] == %{"b" => "number"}

        respond.(env, opts)
      end)

      assert :ok =
               perform_job(MessageProcessor, %{"message_id" => user_message.id})
    end

    test "attaching a FOREIGN step must not egress its IO (regression guard)",
         %{user: user, project: project} do
      # The attacker's own job, in their own project — makes the message itself
      # legitimate/authorized.
      %{job: own_job} = step_in_run(project)

      # A step that lives in a DIFFERENT project the attacker has no rights to.
      foreign_project = insert(:project)
      %{step: foreign_step} = step_in_run(foreign_project)

      # Own job on the message, but a foreign step_id in message_options —
      # exactly the IDOR: step_id is never scoped to the session's project.
      user_message = io_attach_message(user, project, own_job, foreign_step.id)

      respond = apollo_streaming_reply()

      Mox.expect(Lightning.Tesla.Mock, :call, fn env, opts ->
        context = Jason.decode!(env.body)["context"]

        # After the fix, get_step_with_dataclips/… refuses to load a step that
        # isn't reachable from a run in the session's project, so no IO is
        # attached and build_context/2 omits the keys entirely (=> nil once
        # JSON-decoded).
        #
        # ON THE CURRENT VULNERABLE CODE THIS FAILS: context["input"] /
        # ["output"] come back populated with the foreign step's scrubbed
        # structure — that failure *is* the confirmed cross-tenant leak.
        assert context["input"] == nil
        assert context["output"] == nil

        respond.(env, opts)
      end)

      assert :ok =
               perform_job(MessageProcessor, %{"message_id" => user_message.id})
    end

    # --- helpers ---------------------------------------------------------------

    # A step wired to a real run in `project` (via run_step), with input + output
    # dataclips carrying simple bodies so both scrub branches run. Returning the
    # step through a run is what keeps the happy-path test valid after the fix
    # (which scopes step_id to a run in the session's project).
    defp step_in_run(project) do
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)
      snapshot = insert(:snapshot, workflow: workflow)
      work_order = insert(:workorder, workflow: workflow, snapshot: snapshot)

      run =
        insert(:run,
          work_order: work_order,
          snapshot: snapshot,
          dataclip: build(:dataclip, project: project),
          starting_job: job
        )

      step =
        insert(:step,
          job: job,
          snapshot: snapshot,
          input_dataclip: build(:dataclip, project: project, body: %{"a" => 1}),
          output_dataclip: build(:dataclip, project: project, body: %{"b" => 2})
        )

      insert(:run_step, run: run, step: step)

      %{workflow: workflow, job: job, run: run, step: step}
    end

    # A job_code session in `project` requesting IO attachment for `step_id`,
    # plus the user message that carries `job` (so job_chat?/2 routes to the job
    # path). Returns the persisted user message.
    defp io_attach_message(user, project, job, step_id) do
      session =
        insert(:chat_session,
          user: user,
          session_type: "job_code",
          project: project,
          job_id: job.id,
          meta: %{
            "message_options" => %{
              "attach_io_data" => true,
              "step_id" => step_id
            }
          }
        )

      {:ok, updated_session} =
        AiAssistant.save_message(
          session,
          %{role: :user, content: "summarise my step io", user: user, job: job},
          []
        )

      Enum.find(updated_session.messages, &(&1.role == :user))
    end

    defp apollo_streaming_reply do
      Lightning.AiAssistantHelpers.streaming_or_sync_response(%{
        "response" => "AI response",
        "history" => [
          %{"role" => "user", "content" => "test"},
          %{"role" => "assistant", "content" => "AI response"}
        ]
      })
    end
  end
end
