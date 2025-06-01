defmodule LightningWeb.AiAssistant.Modes.WorkflowTemplateTest do
  use Lightning.DataCase, async: true

  alias LightningWeb.Live.AiAssistant.Modes.WorkflowTemplate

  describe "chat_input_disabled?/1" do
    test "disables when user lacks edit permissions" do
      assigns = %{
        can_edit_workflow: false,
        ai_limit_result: :ok,
        endpoint_available?: true,
        pending_message: %{loading: nil}
      }

      assert WorkflowTemplate.chat_input_disabled?(assigns) == true
    end

    test "disables when AI limits reached" do
      assigns = %{
        can_edit_workflow: true,
        ai_limit_result: {:error, :quota_exceeded},
        endpoint_available?: true,
        pending_message: %{loading: nil}
      }

      assert WorkflowTemplate.chat_input_disabled?(assigns) == true
    end

    test "disables when endpoint unavailable" do
      assigns = %{
        can_edit_workflow: true,
        ai_limit_result: :ok,
        endpoint_available?: false,
        pending_message: %{loading: nil}
      }

      assert WorkflowTemplate.chat_input_disabled?(assigns) == true
    end

    test "disables when message is loading" do
      assigns = %{
        can_edit_workflow: true,
        ai_limit_result: :ok,
        endpoint_available?: true,
        pending_message: %{loading: "processing"}
      }

      assert WorkflowTemplate.chat_input_disabled?(assigns) == true
    end

    test "enables when all conditions are met" do
      assigns = %{
        can_edit_workflow: true,
        ai_limit_result: :ok,
        endpoint_available?: true,
        pending_message: %{loading: nil}
      }

      assert WorkflowTemplate.chat_input_disabled?(assigns) == false
    end

    test "does not check job save state (unlike JobCode mode)" do
      assigns = %{
        can_edit_workflow: true,
        ai_limit_result: :ok,
        endpoint_available?: true,
        pending_message: %{loading: nil},
        selected_job: %{__meta__: %{state: :built}}
      }

      assert WorkflowTemplate.chat_input_disabled?(assigns) == false
    end
  end

  describe "input_placeholder/0" do
    test "returns workflow-specific placeholder" do
      assert WorkflowTemplate.input_placeholder() ==
               "Describe the workflow you want to create..."
    end
  end

  describe "chat_title/1" do
    test "uses custom title when available" do
      session = %{title: "Salesforce Integration Workflow"}

      assert WorkflowTemplate.chat_title(session) ==
               "Salesforce Integration Workflow"
    end

    test "uses project name when available" do
      session = %{project: %{name: "Customer Data Platform"}}

      assert WorkflowTemplate.chat_title(session) ==
               "Customer Data Platform Workflow"
    end

    test "falls back to default title" do
      session = %{}
      assert WorkflowTemplate.chat_title(session) == "New Workflow"
    end

    test "prefers custom title over project name" do
      session = %{
        title: "Custom Workflow Name",
        project: %{name: "Some Project"}
      }

      assert WorkflowTemplate.chat_title(session) == "Custom Workflow Name"
    end

    test "handles empty title gracefully" do
      session = %{title: "", project: %{name: "Test Project"}}
      assert WorkflowTemplate.chat_title(session) == "Test Project Workflow"
    end

    test "handles nil project gracefully" do
      session = %{project: nil}
      assert WorkflowTemplate.chat_title(session) == "New Workflow"
    end
  end

  describe "supports_template_generation?/0" do
    test "returns true - workflow mode generates templates" do
      assert WorkflowTemplate.supports_template_generation?() == true
    end
  end

  describe "metadata/0" do
    test "returns correct metadata" do
      meta = WorkflowTemplate.metadata()

      assert meta.name == "Workflow Builder"

      assert meta.description ==
               "Generate complete workflows from your descriptions"

      assert meta.icon == "hero-cpu-chip"
    end
  end

  describe "handle_response_generated/3" do
    test "returns assigns unchanged when no workflow code present" do
      assigns = %{some: "data"}

      session_without_code = %Lightning.AiAssistant.ChatSession{
        messages: [
          %Lightning.AiAssistant.ChatMessage{workflow_code: nil},
          %Lightning.AiAssistant.ChatMessage{workflow_code: ""}
        ]
      }

      ui_callback = fn _event, _data ->
        flunk("UI callback should not be called when no workflow code present")
      end

      result =
        WorkflowTemplate.handle_response_generated(
          assigns,
          session_without_code,
          ui_callback
        )

      assert result == assigns
    end

    test "calls UI callback when workflow code is present" do
      assigns = %{some: "data"}

      session_with_code = %Lightning.AiAssistant.ChatSession{
        messages: [
          %Lightning.AiAssistant.ChatMessage{
            workflow_code: "name: Test Workflow\njobs:\n  - name: fetch_data"
          }
        ]
      }

      test_pid = self()

      ui_callback = fn event, data ->
        send(test_pid, {:ui_callback, event, data})
      end

      result =
        WorkflowTemplate.handle_response_generated(
          assigns,
          session_with_code,
          ui_callback
        )

      assert result == assigns

      assert_received {:ui_callback, :workflow_code_generated,
                       "name: Test Workflow\njobs:\n  - name: fetch_data"}
    end

    test "works with single message containing workflow code" do
      assigns = %{}

      message_with_code = %Lightning.AiAssistant.ChatMessage{
        workflow_code: "name: Simple\njobs: []"
      }

      test_pid = self()
      ui_callback = fn event, data -> send(test_pid, {event, data}) end

      WorkflowTemplate.handle_response_generated(
        assigns,
        message_with_code,
        ui_callback
      )

      assert_received {:workflow_code_generated, "name: Simple\njobs: []"}
    end
  end

  describe "on_session_start/2" do
    test "calls UI callback to clear template" do
      socket = %{assigns: %{test: "data"}}

      test_pid = self()

      ui_callback = fn event, data ->
        send(test_pid, {:ui_callback, event, data})
      end

      result = WorkflowTemplate.on_session_start(socket, ui_callback)

      assert result == socket

      assert_received {:ui_callback, :clear_template, nil}
    end
  end

  describe "disabled_tooltip_message/1" do
    test "returns permission message when user cannot edit" do
      assigns = %{can_edit_workflow: false, ai_limit_result: :ok}

      message = WorkflowTemplate.disabled_tooltip_message(assigns)

      assert message == "You are not authorized to use the AI Assistant"
    end

    test "returns limit message when AI limits exceeded" do
      assigns = %{
        can_edit_workflow: true,
        ai_limit_result: {:error, :quota_exceeded}
      }

      message = WorkflowTemplate.disabled_tooltip_message(assigns)

      assert is_binary(message)
      assert String.contains?(message, "limit")
    end

    test "returns nil when input should be enabled" do
      assigns = %{can_edit_workflow: true, ai_limit_result: :ok}

      message = WorkflowTemplate.disabled_tooltip_message(assigns)

      assert message == nil
    end
  end

  describe "error_message/1" do
    test "formats errors using ErrorHandler" do
      error = {:error, "Something went wrong"}

      message = WorkflowTemplate.error_message(error)

      assert message == "Something went wrong"
    end

    test "handles timeout errors" do
      error = {:error, :timeout}

      message = WorkflowTemplate.error_message(error)

      assert message == "Request timed out. Please try again."
    end
  end

  describe "extract_workflow_code (via handle_response_generated)" do
    test "finds workflow code in session messages" do
      assigns = %{}

      session = %Lightning.AiAssistant.ChatSession{
        messages: [
          %Lightning.AiAssistant.ChatMessage{workflow_code: nil},
          %Lightning.AiAssistant.ChatMessage{workflow_code: ""},
          %Lightning.AiAssistant.ChatMessage{
            workflow_code: "name: Found\njobs: []"
          }
        ]
      }

      test_pid = self()
      ui_callback = fn _event, data -> send(test_pid, {:found, data}) end

      WorkflowTemplate.handle_response_generated(assigns, session, ui_callback)

      assert_received {:found, "name: Found\njobs: []"}
    end

    test "handles empty workflow code gracefully" do
      assigns = %{}

      session = %Lightning.AiAssistant.ChatSession{
        messages: [
          %Lightning.AiAssistant.ChatMessage{workflow_code: ""},
          %Lightning.AiAssistant.ChatMessage{workflow_code: nil}
        ]
      }

      ui_callback = fn _event, _data ->
        flunk("Should not call UI callback for empty workflow code")
      end

      result =
        WorkflowTemplate.handle_response_generated(assigns, session, ui_callback)

      assert result == assigns
    end
  end
end
