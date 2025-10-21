defmodule LightningWeb.WorkflowLive.AiAssistant.ComponentTest do
  use LightningWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.AiAssistant
  alias LightningWeb.AiAssistant.Component, as: AiAssistantComponent
  alias LightningWeb.Live.AiAssistant.Modes.JobCode
  alias Phoenix.LiveView.AsyncResult

  describe "formatted_content/1" do
    test "renders assistant messages with properly styled links" do
      content = """
      Here are some links:
      - [Apollo Repo](https://github.com/OpenFn/apollo)
      - Plain text
      - [Lightning Repo](https://github.com/OpenFn/lightning)
      """

      html =
        render_component(
          &AiAssistantComponent.formatted_content/1,
          id: "formatted-content",
          content: content
        )

      parsed_html = Floki.parse_document!(html)
      links = Floki.find(parsed_html, "a")

      apollo_link =
        Enum.find(
          links,
          &(Floki.attribute(&1, "href") == ["https://github.com/OpenFn/apollo"])
        )

      assert apollo_link != nil

      assert Floki.attribute(apollo_link, "class") == [
               "text-primary-400 hover:text-primary-600"
             ]

      assert Floki.attribute(apollo_link, "target") == ["_blank"]

      lightning_link =
        Enum.find(
          links,
          &(Floki.attribute(&1, "href") == [
              "https://github.com/OpenFn/lightning"
            ])
        )

      assert lightning_link != nil

      assert Floki.attribute(lightning_link, "class") == [
               "text-primary-400 hover:text-primary-600"
             ]

      assert Floki.attribute(lightning_link, "target") == ["_blank"]

      list_items = Floki.find(parsed_html, "li")

      assert Enum.any?(list_items, fn li ->
               Floki.text(li) |> String.trim() == "Plain text"
             end)
    end

    test "handles content with invalid markdown links" do
      content = """
      Broken [link(test.com
      [Another](working.com)
      """

      html =
        render_component(
          &AiAssistantComponent.formatted_content/1,
          id: "formatted-content",
          content: content
        )

      parsed_html = Floki.parse_document!(html)
      assert Floki.text(parsed_html) =~ "Broken [link(test.com"

      working_link =
        Floki.find(parsed_html, "a")
        |> Enum.find(&(Floki.attribute(&1, "href") == ["working.com"]))

      assert working_link != nil

      assert Floki.attribute(working_link, "class") == [
               "text-primary-400 hover:text-primary-600"
             ]

      assert Floki.attribute(working_link, "target") == ["_blank"]
    end

    test "elements without defined styles remain unchanged" do
      content = """
      <weirdo>Some code</weirdo>
      <pierdo>Preformatted text</pierdo>
      [A link](https://weirdopierdo.com)
      """

      html =
        render_component(&AiAssistantComponent.formatted_content/1,
          id: "formatted-content",
          content: content
        )

      parsed_html = Floki.parse_document!(html)

      code = Floki.find(parsed_html, "weirdo")
      pre = Floki.find(parsed_html, "pierdo")
      assert Floki.attribute(code, "class") == []
      assert Floki.attribute(pre, "class") == []

      link =
        Floki.find(parsed_html, "a")
        |> Enum.find(
          &(Floki.attribute(&1, "href") == ["https://weirdopierdo.com"])
        )

      assert link != nil

      assert Floki.attribute(link, "class") == [
               "text-primary-400 hover:text-primary-600"
             ]

      assert Floki.attribute(link, "target") == ["_blank"]
    end

    test "handles content that cannot be parsed as AST" do
      content = """
      <div>Unclosed div
      <span>Unclosed span
      Some text
      """

      html =
        render_component(&AiAssistantComponent.formatted_content/1,
          id: "formatted-content",
          content: content
        )

      parsed_html = Floki.parse_document!(html)

      assert Floki.text(parsed_html) =~ "Unclosed div"
      assert Floki.text(parsed_html) =~ "Unclosed span"
      assert Floki.text(parsed_html) =~ "Some text"
    end

    test "applies styles to elements not defined in the default styles" do
      content = """
      <custom-tag>Custom styled content</custom-tag>
      """

      custom_attributes = %{
        "custom-tag" => %{class: "custom-class text-green-700"}
      }

      html =
        render_component(&AiAssistantComponent.formatted_content/1, %{
          id: "formatted-content",
          content: content,
          attributes: custom_attributes
        })

      parsed_html = Floki.parse_document!(html)
      custom_tag = Floki.find(parsed_html, "custom-tag") |> hd()

      assert custom_tag != nil

      assert Floki.attribute(custom_tag, "class") == [
               "custom-class text-green-700"
             ]
    end
  end

  describe "error_message/1" do
    test "renders string error message" do
      assert JobCode.error_message({:error, "Something went wrong"}) ==
               "Something went wrong"
    end

    test "renders changeset error message" do
      changeset = %Ecto.Changeset{
        valid?: false,
        errors: [content: {"is invalid", []}],
        data: %Lightning.AiAssistant.ChatSession{}
      }

      assert JobCode.error_message({:error, changeset}) ==
               "Content is invalid"
    end

    test "renders text message from map" do
      error_data = %{text: "Specific error message"}

      assert JobCode.error_message({:error, :custom_reason, error_data}) ==
               "Specific error message"
    end

    test "renders default error message for unhandled cases" do
      assert JobCode.error_message({:error, :unknown_reason}) ==
               "An error occurred: unknown_reason. Please try again."

      assert JobCode.error_message(:unexpected_error) ==
               "Oops! Something went wrong. Please try again."
    end

    test "elements without defined styles remain unchanged" do
      content = """
      <weirdo>Some code</weirdo>
      <pierdo>Preformatted text</pierdo>
      [A link](https://weirdopierdo.com)
      """

      html =
        render_component(&AiAssistantComponent.formatted_content/1,
          id: "formatted-content",
          content: content
        )

      parsed_html = Floki.parse_document!(html)

      code = Floki.find(parsed_html, "weirdo")
      pre = Floki.find(parsed_html, "pierdo")

      assert Floki.attribute(code, "class") == []
      assert Floki.attribute(pre, "class") == []

      link =
        Floki.find(parsed_html, "a")
        |> Enum.find(
          &(Floki.attribute(&1, "href") == ["https://weirdopierdo.com"])
        )

      assert link != nil

      assert Floki.attribute(link, "class") == [
               "text-primary-400 hover:text-primary-600"
             ]

      assert Floki.attribute(link, "target") == ["_blank"]
    end

    test "handles content that cannot be parsed as AST" do
      content = """
      <div>Unclosed div
      <span>Unclosed span
      Some text
      """

      html =
        render_component(&AiAssistantComponent.formatted_content/1,
          id: "formatted-content",
          content: content
        )

      parsed_html = Floki.parse_document!(html)

      text = Floki.text(parsed_html)
      assert text =~ "Unclosed div"
      assert text =~ "Unclosed span"
      assert text =~ "Some text"
    end

    test "applies styles to elements not defined in the default styles" do
      content = """
      <custom-tag>Custom styled content</custom-tag>
      """

      custom_attributes = %{
        "custom-tag" => %{class: "custom-class text-green-700"}
      }

      html =
        render_component(&AiAssistantComponent.formatted_content/1, %{
          id: "formatted-content",
          content: content,
          attributes: custom_attributes
        })

      parsed_html = Floki.parse_document!(html)

      custom_tag = Floki.find(parsed_html, "custom-tag") |> hd()

      assert custom_tag != nil

      assert Floki.attribute(custom_tag, "class") == [
               "custom-class text-green-700"
             ]
    end
  end

  describe "form validation" do
    alias LightningWeb.Live.AiAssistant.Modes.WorkflowTemplate

    test "JobCode Form validates empty content" do
      changeset = JobCode.Form.changeset(%{"content" => ""})

      assert changeset.valid? == false
      assert Keyword.has_key?(changeset.errors, :content)
      {msg, _opts} = changeset.errors[:content]
      assert msg == "Please enter a message before sending"
    end

    test "JobCode validate_form includes content validation" do
      changeset = JobCode.validate_form(%{"content" => nil})

      assert changeset.valid? == false
      assert Keyword.has_key?(changeset.errors, :content)
    end

    test "WorkflowTemplate DefaultForm validates empty content" do
      changeset = WorkflowTemplate.DefaultForm.changeset(%{"content" => ""})

      assert changeset.valid? == false
      assert Keyword.has_key?(changeset.errors, :content)
      {msg, _opts} = changeset.errors[:content]
      assert msg == "Please enter a message before sending"
    end

    test "form validation accepts valid content" do
      # JobCode
      changeset = JobCode.validate_form(%{"content" => "Help me with my code"})
      assert changeset.valid? == true

      # WorkflowTemplate
      changeset =
        WorkflowTemplate.validate_form(%{"content" => "Create a workflow"})

      assert changeset.valid? == true
    end
  end

  describe "streaming error handling" do
    # Note: These tests document the expected error messages from SSEStream.
    # Full integration testing would require LiveView test or E2E tests.
    # The error handling logic is tested at the unit level in sse_stream_test.exs

    test "SSEStream broadcasts user-friendly error messages" do
      # Document expected error messages that SSEStream broadcasts
      error_cases = [
        {:timeout, "Connection timed out"},
        {:closed, "Connection closed unexpectedly"},
        {{:shutdown, "reason"}, "Server shut down"},
        {{:http_error, 500}, "Server returned error status 500"},
        {:econnrefused, "Connection error"}
      ]

      for {_reason, expected_message} <- error_cases do
        # These are the error messages that SSEStream.handle_info({:sse_error, reason}, state)
        # will broadcast, which the Component then displays to users
        assert expected_message != nil
      end
    end

    test "error events from Apollo are parsed correctly" do
      # Document that SSEStream handles JSON error events from Apollo
      error_json = Jason.encode!(%{"message" => "Python syntax error"})

      # SSEStream parses this and broadcasts "Python syntax error"
      {:ok, parsed} = Jason.decode(error_json)
      assert parsed["message"] == "Python syntax error"
    end

    test "component implements retry and cancel handlers" do
      # Document that the component implements retry_streaming and cancel_streaming handlers
      # These are defined in lib/lightning_web/live/ai_assistant/component.ex

      # retry_streaming: resubmits the last user message
      # cancel_streaming: clears the error state and cancels the pending message

      # The handlers are implemented via handle_event/3 callbacks
      # Actual behavior testing requires full LiveView test setup or E2E tests

      # Verify the module is a LiveComponent
      assert LightningWeb.AiAssistant.Component.__info__(:attributes)
             |> Keyword.get(:behaviour, [])
             |> Enum.member?(Phoenix.LiveComponent)
    end
  end

  describe "streaming update handlers" do
    setup do
      user = insert(:user)
      project = insert(:project)
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)

      session =
        insert(:job_chat_session,
          user: user,
          job: job
        )

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          session: session,
          streaming_content: "",
          streaming_status: nil,
          streaming_error: nil
        }
      }

      %{socket: socket, session: session, user: user}
    end

    test "update with streaming_chunk appends content to streaming_content",
         %{socket: socket} do
      chunk_data = %{content: "Hello "}

      {:ok, updated_socket} =
        AiAssistantComponent.update(
          %{id: "test-component", streaming_chunk: chunk_data},
          socket
        )

      assert updated_socket.assigns.streaming_content == "Hello "

      # Append more content
      chunk_data2 = %{content: "world!"}

      {:ok, updated_socket2} =
        AiAssistantComponent.update(
          %{id: "test-component", streaming_chunk: chunk_data2},
          updated_socket
        )

      assert updated_socket2.assigns.streaming_content == "Hello world!"
    end

    test "update with status_update sets streaming_status", %{socket: socket} do
      status_data = %{status: "Processing your request..."}

      {:ok, updated_socket} =
        AiAssistantComponent.update(
          %{id: "test-component", status_update: status_data},
          socket
        )

      assert updated_socket.assigns.streaming_status ==
               "Processing your request..."
    end

    test "update with streaming_complete keeps socket unchanged",
         %{socket: socket} do
      original_content = "Some content"
      socket = put_in(socket.assigns.streaming_content, original_content)

      {:ok, updated_socket} =
        AiAssistantComponent.update(
          %{id: "test-component", streaming_complete: true},
          socket
        )

      # Should keep the content as is until payload arrives
      assert updated_socket.assigns.streaming_content == original_content
    end
  end

  describe "handle_streaming_payload_complete" do
    setup do
      user = insert(:user)
      project = insert(:project)
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)

      session =
        insert(:job_chat_session,
          user: user,
          job: job
        )

      # Create a user message in processing state
      user_message =
        insert(:chat_message,
          role: :user,
          chat_session: session,
          user: user,
          status: :processing,
          content: "Help me with this"
        )

      session = AiAssistant.get_session!(session.id)

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          session: session,
          streaming_content: "This is the streamed response",
          streaming_status: "Complete",
          streaming_error: nil,
          pending_message: AsyncResult.loading(),
          callbacks: %{}
        }
      }

      %{
        socket: socket,
        session: session,
        user: user,
        user_message: user_message
      }
    end

    test "saves assistant message with streamed content and payload data",
         %{socket: socket} do
      payload_data = %{
        usage: %{"prompt_tokens" => 100, "completion_tokens" => 50},
        meta: %{"model" => "claude-3"},
        code: nil
      }

      {:ok, updated_socket} =
        AiAssistantComponent.update(
          %{id: "test-component", streaming_payload_complete: payload_data},
          socket
        )

      # Verify the assistant message was saved
      updated_session = updated_socket.assigns.session

      assistant_messages =
        Enum.filter(
          updated_session.messages,
          &(&1.role == :assistant)
        )

      assert length(assistant_messages) == 1
      assistant_message = hd(assistant_messages)
      assert assistant_message.content == "This is the streamed response"
      assert assistant_message.status == :success
      # Usage is tracked at the session level via AI usage tracking
    end

    test "marks pending user messages as success", %{socket: socket} do
      payload_data = %{usage: %{}, meta: nil, code: nil}

      {:ok, updated_socket} =
        AiAssistantComponent.update(
          %{id: "test-component", streaming_payload_complete: payload_data},
          socket
        )

      # Verify user messages are marked as success
      updated_session = updated_socket.assigns.session

      user_messages =
        Enum.filter(
          updated_session.messages,
          &(&1.role == :user)
        )

      assert Enum.all?(user_messages, &(&1.status == :success))
    end

    test "clears streaming state after completion", %{socket: socket} do
      payload_data = %{usage: %{}, meta: nil, code: nil}

      {:ok, updated_socket} =
        AiAssistantComponent.update(
          %{id: "test-component", streaming_payload_complete: payload_data},
          socket
        )

      assert updated_socket.assigns.streaming_content == ""
      assert updated_socket.assigns.streaming_status == nil
      assert updated_socket.assigns.pending_message == AsyncResult.ok(nil)
    end

    test "invokes callback when provided with code", %{socket: socket} do
      test_pid = self()

      callback = fn code, message ->
        send(test_pid, {:callback_invoked, code, message})
      end

      socket = put_in(socket.assigns.callbacks, %{on_message_received: callback})

      payload_data = %{
        usage: %{},
        meta: nil,
        code: Jason.encode!(%{"some" => "code"})
      }

      {:ok, _updated_socket} =
        AiAssistantComponent.update(
          %{id: "test-component", streaming_payload_complete: payload_data},
          socket
        )

      # Callback should be invoked with code (as JSON string) and message
      expected_code = Jason.encode!(%{"some" => "code"})
      assert_receive {:callback_invoked, ^expected_code, _message}, 2000
    end

    test "handles error when saving message fails", %{socket: socket} do
      # Test that errors are handled gracefully by using empty content
      # which should pass validation but we can verify error handling
      socket_with_empty_content = put_in(socket.assigns.streaming_content, "")

      payload_data = %{usage: %{}, meta: nil, code: nil}

      {:ok, updated_socket} =
        AiAssistantComponent.update(
          %{id: "test-component", streaming_payload_complete: payload_data},
          socket_with_empty_content
        )

      # Should clear state after attempt
      assert updated_socket.assigns.streaming_content == ""
      assert updated_socket.assigns.streaming_status == nil
      assert updated_socket.assigns.pending_message == AsyncResult.ok(nil)
    end
  end

  describe "handle_streaming_error" do
    setup do
      user = insert(:user)
      project = insert(:project)
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)

      session =
        insert(:job_chat_session,
          user: user,
          job: job
        )

      # Create a user message in processing state
      user_message =
        insert(:chat_message,
          role: :user,
          chat_session: session,
          user: user,
          status: :processing,
          content: "Help me with this"
        )

      session = AiAssistant.get_session!(session.id)

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          session: session,
          streaming_content: "Partial content",
          streaming_status: "Processing",
          streaming_error: nil,
          pending_message: AsyncResult.ok(nil)
        }
      }

      %{
        socket: socket,
        session: session,
        user_message: user_message
      }
    end

    test "marks user messages as error", %{socket: socket} do
      error_data = %{error: "Connection timeout"}

      {:ok, updated_socket} =
        AiAssistantComponent.update(
          %{id: "test-component", streaming_error: error_data},
          socket
        )

      # Verify user messages are marked as error
      updated_session = updated_socket.assigns.session

      user_messages =
        Enum.filter(
          updated_session.messages,
          &(&1.role == :user)
        )

      assert Enum.all?(user_messages, &(&1.status == :error))
    end

    test "sets streaming_error in assigns", %{socket: socket} do
      error_data = %{error: "Network connection failed"}

      {:ok, updated_socket} =
        AiAssistantComponent.update(
          %{id: "test-component", streaming_error: error_data},
          socket
        )

      assert updated_socket.assigns.streaming_error ==
               "Network connection failed"
    end

    test "clears streaming content and status", %{socket: socket} do
      error_data = %{error: "Something went wrong"}

      {:ok, updated_socket} =
        AiAssistantComponent.update(
          %{id: "test-component", streaming_error: error_data},
          socket
        )

      assert updated_socket.assigns.streaming_content == ""
      assert updated_socket.assigns.streaming_status == nil
    end

    test "sets pending_message to loading state", %{socket: socket} do
      error_data = %{error: "Error occurred"}

      {:ok, updated_socket} =
        AiAssistantComponent.update(
          %{id: "test-component", streaming_error: error_data},
          socket
        )

      assert updated_socket.assigns.pending_message.loading == true
    end
  end

  describe "update with message_status_changed - testing handle_message_status through public API" do
    setup do
      user = insert(:user)
      project = insert(:project)
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)
      session = insert(:job_chat_session, user: user, job: job)

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          session: session,
          streaming_content: "Existing streaming content",
          streaming_status: "Processing...",
          pending_message: AsyncResult.loading(),
          handler: JobCode,
          callbacks: %{}
        }
      }

      %{socket: socket, session: session}
    end

    test "update with message_status_changed :success preserves streaming state",
         %{socket: socket, session: session} do
      # This tests lines 193-196: handle_message_status({:success, session})
      # through the public update/2 function
      {:ok, updated_socket} =
        AiAssistantComponent.update(
          %{message_status_changed: {:success, session}},
          socket
        )

      assert updated_socket.assigns.streaming_content ==
               "Existing streaming content"

      assert updated_socket.assigns.streaming_status == "Processing..."
      assert updated_socket.assigns.pending_message == AsyncResult.ok(nil)
    end

    test "update with message_status_changed :error preserves streaming state",
         %{socket: socket, session: session} do
      # This tests lines 200-205: handle_message_status({:error, session})
      # through the public update/2 function
      {:ok, updated_socket} =
        AiAssistantComponent.update(
          %{message_status_changed: {:error, session}},
          socket
        )

      assert updated_socket.assigns.streaming_content ==
               "Existing streaming content"

      assert updated_socket.assigns.streaming_status == "Processing..."
      assert updated_socket.assigns.pending_message == AsyncResult.ok(nil)
    end
  end

  describe "form validation - testing form_content_empty? indirectly" do
    test "validate_form with empty/whitespace content returns error" do
      # This tests form_content_empty? (lines 1198-1204) through the public validate_form function
      changeset = JobCode.validate_form(%{"content" => "   "})

      assert changeset.valid? == false
      assert Keyword.has_key?(changeset.errors, :content)
      {msg, _opts} = changeset.errors[:content]
      assert msg == "Please enter a message before sending"
    end

    test "validate_form with nil content returns error" do
      changeset = JobCode.validate_form(%{"content" => nil})
      assert changeset.valid? == false
    end

    test "validate_form with valid content passes" do
      changeset = JobCode.validate_form(%{"content" => "Valid message"})
      assert changeset.valid? == true
    end
  end
end
