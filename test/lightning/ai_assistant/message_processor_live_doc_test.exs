defmodule Lightning.AiAssistant.MessageProcessorLiveDocTest do
  # async: false — the collaboration document processes (SharedDoc,
  # PersistenceWriter) run outside the test process and need shared access to
  # the SQL sandbox.
  use Lightning.DataCase, async: false

  @moduletag :capture_log

  import Mox
  import Lightning.Factories

  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.MessageProcessor
  alias Yex.Sync.SharedDoc

  setup :set_mox_from_context
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
    # Queue jobs instead of running them inline at save_message time, so the
    # test controls when the processor runs (after the Tesla expectation is
    # in place).
    Process.put(:oban_testing, :manual)
    :ok
  end

  test "prefers the live collaboration doc over the saved workflow state",
       %{user: user, project: project} do
    workflow =
      insert(:simple_workflow, name: "Saved Stale Name", project: project)

    document_name = "workflow:#{workflow.id}"

    {:ok, _pid} = Lightning.Collaborate.start_document(workflow, document_name)

    on_exit(fn ->
      Lightning.CollaborationHelpers.ensure_doc_supervisor_stopped(workflow.id)
    end)

    shared_doc_pid =
      Lightning.Collaboration.Session.lookup_shared_doc(document_name)

    assert is_pid(shared_doc_pid)

    # Simulate an unsaved collaborative edit: rename the workflow in the Y.Doc
    # without saving it to the database.
    SharedDoc.update_doc(shared_doc_pid, fn doc ->
      doc
      |> Yex.Doc.get_map("workflow")
      |> Yex.Map.set("name", "Live Edited Name")
    end)

    global_meta = %{
      "message_options" => %{
        "use_global_assistant" => true,
        "page" => "/projects/p1/workflows/w1"
      }
    }

    session =
      insert(:chat_session,
        user: user,
        session_type: "workflow_template",
        project: project,
        workflow: workflow,
        job_id: nil,
        meta: global_meta
      )

    # The client sent no code with the message
    {:ok, updated_session} =
      AiAssistant.save_message(
        session,
        %{role: :user, content: "help with my workflow", user: user},
        meta: global_meta
      )

    user_message = Enum.find(updated_session.messages, &(&1.role == :user))
    assert is_nil(user_message.code)

    test_pid = self()

    Mox.expect(Lightning.Tesla.Mock, :call, fn %{url: url, body: body}, _opts ->
      assert url =~ "/services/global_chat/stream"
      send(test_pid, {:apollo_payload, Jason.decode!(body)})

      {:ok,
       %Tesla.Env{
         status: 200,
         headers: [{"content-type", "text/event-stream"}],
         body:
           "event: complete\ndata: #{Jason.encode!(%{"response" => "ok", "usage" => %{}})}\n\n"
       }}
    end)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert :ok =
                 perform_job(MessageProcessor, %{
                   "message_id" => user_message.id
                 })
      end)

    assert_receive {:apollo_payload, payload}
    assert %{"workflow_yaml" => workflow_yaml} = payload

    # The YAML reflects the live (unsaved) doc, not the stale saved state
    assert workflow_yaml =~ "Live Edited Name"
    refute workflow_yaml =~ "Saved Stale Name"
    assert workflow_yaml =~ workflow.id
    [job] = workflow.jobs
    assert workflow_yaml =~ job.name

    assert log =~ "built it server-side from the live collaboration doc"
  end
end
