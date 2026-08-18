defmodule Lightning.AiAssistant.StreamFailureTest do
  @moduledoc """
  What survives when Apollo stops talking partway through a reply.

  These drive a real socket rather than `Lightning.Tesla.Mock`, because the
  behaviour under test only exists once something walks the lazy body stream.
  A raw listener is used rather than Bypass: these connections are hung up
  mid-response, and Bypass links its plug to the test process, so a plug dying
  on a closed socket takes the test with it.
  """
  use Lightning.DataCase, async: false

  import Ecto.Query
  import Lightning.Factories
  import Mox

  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.ChatMessage

  setup :verify_on_exit!

  # Deliberately not tighter. This becomes the adapter's receive_timeout, which
  # bounds the wait for the response headers as well as the gap between chunks,
  # so a value chosen to keep the test quick expires on the headers instead when
  # the machine is busy. The request then fails outright, no partial is saved,
  # and every test in here dies looking at a nil message rather than failing on
  # what it was checking. The servers below stay quiet for ten times this.
  @idle_timeout 1_000

  defp chunk(frame) do
    [Integer.to_string(byte_size(frame), 16), "\r\n", frame, "\r\n"]
  end

  defp sse(event, data) do
    "event: #{event}\ndata: #{Jason.encode!(data)}\n\n"
  end

  defp text_delta(text) do
    sse("content_block_delta", %{
      "type" => "content_block_delta",
      "delta" => %{"type" => "text_delta", "text" => text}
    })
  end

  # Sends every frame it is given, then holds the connection open in silence
  # until the idle timeout gives up on it. The `complete` event never arrives.
  defp apollo_that_dies(frames) do
    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listen)

    spawn(fn ->
      {:ok, socket} = :gen_tcp.accept(listen)
      {:ok, _request} = :gen_tcp.recv(socket, 0, 5_000)

      :gen_tcp.send(socket, [
        "HTTP/1.1 200 OK\r\n",
        "Content-Type: text/event-stream\r\n",
        "Transfer-Encoding: chunked\r\n\r\n",
        Enum.map(frames, &chunk/1)
      ])

      Process.sleep(@idle_timeout * 10)
      :gen_tcp.close(socket)
      :gen_tcp.close(listen)
    end)

    port
  end

  defp stub_apollo(port) do
    Mox.stub(Lightning.MockConfig, :apollo, fn
      :endpoint -> "http://localhost:#{port}"
      :ai_assistant_api_key -> "key"
      :connect_timeout -> 1_000
      :idle_timeout -> @idle_timeout
      :request_timeout -> 30_000
    end)

    previous = Application.get_env(:tesla, :adapter)
    Application.put_env(:tesla, :adapter, {Tesla.Adapter.Finch, []})
    on_exit(fn -> Application.put_env(:tesla, :adapter, previous) end)
  end

  defp saved_message(session) do
    Lightning.Repo.one(
      from(m in ChatMessage,
        where: m.chat_session_id == ^session.id and m.role == :assistant
      )
    )
  end

  defp job_session do
    insert(:chat_session,
      session_type: "job_code",
      job: insert(:job, workflow: insert(:workflow)),
      user: insert(:user)
    )
    |> Lightning.Repo.preload(:messages)
  end

  defp workflow_session do
    project = insert(:project)

    insert(:chat_session,
      session_type: "workflow_template",
      project: project,
      workflow: insert(:workflow, project: project),
      user: insert(:user)
    )
    |> Lightning.Repo.preload(:messages)
  end

  describe "a job chat stream that dies" do
    test "keeps the text the user already watched appear" do
      port = apollo_that_dies([text_delta("Use "), text_delta("fn(state)")])
      stub_apollo(port)

      session = job_session()

      assert {:error, _} = AiAssistant.query_stream(session, "how?")

      message = saved_message(session)

      assert message.content == "Use fn(state)"
      assert message.status == :error
      assert message.failure_category == :incomplete_response
    end

    test "leaves plain text as a flat message, with no timeline" do
      port = apollo_that_dies([text_delta("Just prose")])
      stub_apollo(port)

      session = job_session()

      assert {:error, _} = AiAssistant.query_stream(session, "how?")

      # A reply with no status in it renders the same from `content` alone.
      assert saved_message(session).response_segments in [nil, []]
    end
  end

  describe "a workflow chat stream that dies" do
    test "keeps the YAML that arrived ahead of the text" do
      port =
        apollo_that_dies([
          sse("changes", %{"yaml" => "name: my-workflow\njobs: {}\n"}),
          text_delta("Added the step you asked for")
        ])

      stub_apollo(port)

      session = workflow_session()

      assert {:error, _} = AiAssistant.query_workflow_stream(session, "build it")

      message = saved_message(session)

      assert message.code == "name: my-workflow\njobs: {}\n"
      assert message.content == "Added the step you asked for"
      assert message.failure_category == :incomplete_response
    end

    test "keeps the status updates in the order they were shown" do
      port =
        apollo_that_dies([
          text_delta("Adding a step"),
          sse("status", %{"type" => "status", "content" => "Validating..."}),
          text_delta("Nearly there")
        ])

      stub_apollo(port)

      session = workflow_session()

      assert {:error, _} = AiAssistant.query_workflow_stream(session, "build it")

      assert [
               %{type: :text, content: "Adding a step"},
               %{type: :status, content: "Validating..."},
               %{type: :text, content: "Nearly there"}
             ] =
               saved_message(session).response_segments
    end

    test "a blank status update does not cost us the whole partial" do
      # validate_required trims before it checks, so whitespace-only content
      # fails the embed and would take the text down with it.
      port =
        apollo_that_dies([
          text_delta("Adding a step"),
          sse("status", %{"type" => "status", "content" => "   "}),
          sse("status", %{"type" => "status", "content" => "Validating..."})
        ])

      stub_apollo(port)

      session = workflow_session()

      assert {:error, _} = AiAssistant.query_workflow_stream(session, "build it")

      message = saved_message(session)

      assert message.content == "Adding a step"

      assert [
               %{type: :text, content: "Adding a step"},
               %{type: :status, content: "Validating..."}
             ] = message.response_segments
    end

    test "a reply of nothing but whitespace saves no message at all" do
      port = apollo_that_dies([text_delta("   \n  ")])

      stub_apollo(port)

      session = workflow_session()

      assert {:error, _} = AiAssistant.query_workflow_stream(session, "build it")

      # Not a message reading "(no response)". Whitespace is nothing arriving,
      # and the panel should show the error rather than an empty reply.
      refute saved_message(session)
    end
  end

  describe "a global chat stream that dies" do
    test "keeps the text and the YAML" do
      port =
        apollo_that_dies([
          text_delta("Here is a workflow"),
          sse("changes", %{"yaml" => "name: generated\n"})
        ])

      stub_apollo(port)

      session = workflow_session()

      assert {:error, _} = AiAssistant.query_global_stream(session, "make one")

      message = saved_message(session)

      assert message.content == "Here is a workflow"
      assert message.code == "name: generated\n"
    end
  end
end
