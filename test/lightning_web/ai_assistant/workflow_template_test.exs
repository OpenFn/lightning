defmodule LightningWeb.AiAssistant.Modes.WorkflowTemplateTest do
  use Lightning.DataCase, async: true

  alias LightningWeb.Live.AiAssistant.Modes.WorkflowTemplate

  describe "chat_input_disabled?/1" do
    test "disables when user lacks edit permissions" do
      assigns = %{
        can_edit: false,
        ai_limit_result: :ok,
        endpoint_available: true,
        pending_message: %{loading: nil}
      }

      assert WorkflowTemplate.chat_input_disabled?(assigns) == true
    end

    test "disables when AI limits reached" do
      assigns = %{
        can_edit: true,
        ai_limit_result: {:error, :quota_exceeded},
        endpoint_available: true,
        pending_message: %{loading: nil}
      }

      assert WorkflowTemplate.chat_input_disabled?(assigns) == true
    end

    test "disables when endpoint unavailable" do
      assigns = %{
        can_edit: true,
        ai_limit_result: :ok,
        endpoint_available: false,
        pending_message: %{loading: nil}
      }

      assert WorkflowTemplate.chat_input_disabled?(assigns) == true
    end

    test "disables when message is loading" do
      assigns = %{
        can_edit: true,
        ai_limit_result: :ok,
        endpoint_available: true,
        pending_message: %{loading: "processing"}
      }

      assert WorkflowTemplate.chat_input_disabled?(assigns) == true
    end

    test "enables when all conditions are met" do
      assigns = %{
        can_edit: true,
        ai_limit_result: :ok,
        endpoint_available: true,
        pending_message: %{loading: nil}
      }

      assert WorkflowTemplate.chat_input_disabled?(assigns) == false
    end

    test "does not check job save state (unlike JobCode mode)" do
      assigns = %{
        can_edit: true,
        ai_limit_result: :ok,
        endpoint_available: true,
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

  describe "metadata/0" do
    test "returns correct metadata" do
      meta = WorkflowTemplate.metadata()

      assert meta.name == "Workflow Builder"

      assert meta.description ==
               "Generate complete workflows from your descriptions"

      assert meta.icon == "hero-cpu-chip"
      assert meta.chat_param == "w-chat"
    end
  end

  describe "disabled_tooltip_message/1" do
    test "returns permission message when user cannot edit" do
      assigns = %{can_edit: false, ai_limit_result: :ok}

      message = WorkflowTemplate.disabled_tooltip_message(assigns)

      assert message == "You are not authorized to use the AI Assistant"
    end

    test "returns quota exceeded message when AI limits reached" do
      assigns = %{
        can_edit: true,
        ai_limit_result: {:error, :quota_exceeded}
      }

      message = WorkflowTemplate.disabled_tooltip_message(assigns)

      assert message ==
               "AI usage limit reached. Please try again later or contact support."
    end

    test "returns rate limited message when rate limited" do
      assigns = %{
        can_edit: true,
        ai_limit_result: {:error, :rate_limited}
      }

      message = WorkflowTemplate.disabled_tooltip_message(assigns)

      assert message ==
               "Too many requests. Please wait a moment before trying again."
    end

    test "returns nil when input should be enabled" do
      assigns = %{can_edit: true, ai_limit_result: :ok}

      message = WorkflowTemplate.disabled_tooltip_message(assigns)

      assert message == nil
    end
  end

  describe "error_message/1" do
    test "formats string errors" do
      error = {:error, "Something went wrong"}
      message = WorkflowTemplate.error_message(error)
      assert message == "Something went wrong"
    end

    test "formats timeout errors" do
      error = {:error, :timeout}
      message = WorkflowTemplate.error_message(error)
      assert message == "Request timed out. Please try again."
    end

    test "formats connection errors" do
      error = {:error, :econnrefused}
      message = WorkflowTemplate.error_message(error)
      assert message == "Unable to reach the AI server. Please try again later."
    end

    test "formats generic errors" do
      error = "unexpected error"
      message = WorkflowTemplate.error_message(error)
      assert message == "Oops! Something went wrong. Please try again."
    end
  end

  describe "callbacks" do
    test "on_message_send/1 invokes callback if present" do
      test_pid = self()

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          callbacks: %{
            on_message_send: fn -> send(test_pid, :message_sent) end
          }
        }
      }

      result = WorkflowTemplate.on_message_send(socket)
      assert result == socket
      assert_received :message_sent
    end

    test "on_message_send/1 returns socket unchanged if no callback" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{callbacks: %{}}
      }

      result = WorkflowTemplate.on_message_send(socket)
      assert result == socket
    end

    test "on_message_received/2 extracts code from session" do
      test_pid = self()

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          callbacks: %{
            on_message_received: fn code, session ->
              send(test_pid, {:received, code, session.id})
            end
          }
        }
      }

      session = %Lightning.AiAssistant.ChatSession{
        id: "session-123",
        messages: [
          %Lightning.AiAssistant.ChatMessage{code: nil},
          %Lightning.AiAssistant.ChatMessage{code: ""},
          %Lightning.AiAssistant.ChatMessage{code: "name: Test\njobs: []"}
        ]
      }

      result = WorkflowTemplate.on_message_received(socket, session)
      assert result == socket
      assert_received {:received, "name: Test\njobs: []", "session-123"}
    end

    test "on_message_selected/2 extracts code from message" do
      test_pid = self()

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          callbacks: %{
            on_message_selected: fn code, message ->
              send(test_pid, {:selected, code, message.id})
            end
          }
        }
      }

      message = %Lightning.AiAssistant.ChatMessage{
        id: "msg-123",
        code: "name: Selected\njobs: []"
      }

      result = WorkflowTemplate.on_message_selected(socket, message)
      assert result == socket
      assert_received {:selected, "name: Selected\njobs: []", "msg-123"}
    end

    test "callbacks handle nil code gracefully" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          callbacks: %{
            on_message_selected: fn _code, _msg ->
              flunk("Should not call callback for nil code")
            end
          }
        }
      }

      message = %Lightning.AiAssistant.ChatMessage{code: nil}

      result = WorkflowTemplate.on_message_selected(socket, message)
      assert result == socket
    end

    test "callbacks handle empty code gracefully" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          callbacks: %{
            on_message_selected: fn _code, _msg ->
              flunk("Should not call callback for empty code")
            end
          }
        }
      }

      message = %Lightning.AiAssistant.ChatMessage{code: ""}

      result = WorkflowTemplate.on_message_selected(socket, message)
      assert result == socket
    end
  end

  describe "form handling" do
    test "validate_form/1 creates changeset from params" do
      params = %{"content" => "test content"}
      changeset = WorkflowTemplate.validate_form(params)

      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_field(changeset, :content) == "test content"
    end

    test "extract_form_options/1 returns empty list" do
      changeset = WorkflowTemplate.validate_form(%{"content" => "test"})
      options = WorkflowTemplate.extract_form_options(changeset)

      assert options == []
    end
  end

  # Add these test blocks to the existing test file:

  describe "on_session_close/1" do
    test "invokes callback if present" do
      test_pid = self()

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          callbacks: %{
            on_session_close: fn -> send(test_pid, :session_closed) end
          }
        }
      }

      result = WorkflowTemplate.on_session_close(socket)
      assert result == socket
      assert_received :session_closed
    end

    test "returns socket unchanged if no callback" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{callbacks: %{}}
      }

      result = WorkflowTemplate.on_session_close(socket)
      assert result == socket
    end
  end

  describe "on_session_open/2" do
    test "extracts code when selected_message is nil" do
      test_pid = self()

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          selected_message: nil,
          callbacks: %{
            on_session_open: fn code, session ->
              send(test_pid, {:opened, code, session.id})
            end
          }
        }
      }

      session = %Lightning.AiAssistant.ChatSession{
        id: "session-456",
        messages: [
          %Lightning.AiAssistant.ChatMessage{code: "name: Open\njobs: []"}
        ]
      }

      result = WorkflowTemplate.on_session_open(socket, session)
      assert result == socket
      assert_received {:opened, "name: Open\njobs: []", "session-456"}
    end

    test "skips extraction when selected_message exists" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          selected_message: %{id: "existing"},
          callbacks: %{
            on_session_open: fn _code, _session ->
              flunk("Should not call callback when message is selected")
            end
          }
        }
      }

      session = %Lightning.AiAssistant.ChatSession{
        messages: [
          %Lightning.AiAssistant.ChatMessage{code: "name: Test\njobs: []"}
        ]
      }

      result = WorkflowTemplate.on_session_open(socket, session)
      assert result == socket
    end
  end

  describe "form_module/0" do
    test "returns the default form module" do
      assert WorkflowTemplate.form_module() == WorkflowTemplate.DefaultForm
    end
  end

  describe "edge cases" do
    test "extract_code handles session with no messages" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          selected_message: nil,
          callbacks: %{
            on_session_open: fn _code, _session ->
              flunk("Should not call callback for empty messages")
            end
          }
        }
      }

      session = %Lightning.AiAssistant.ChatSession{
        messages: []
      }

      result = WorkflowTemplate.on_session_open(socket, session)
      assert result == socket
    end

    test "handles code in different positions" do
      test_pid = self()

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          callbacks: %{
            on_message_received: fn code, _session ->
              send(test_pid, {:found_code, code})
            end
          }
        }
      }

      # Code should be found from the last valid message (reverse order)
      session = %Lightning.AiAssistant.ChatSession{
        messages: [
          %Lightning.AiAssistant.ChatMessage{code: "name: First\njobs: []"},
          %Lightning.AiAssistant.ChatMessage{code: nil},
          %Lightning.AiAssistant.ChatMessage{code: "name: Last\njobs: []"}
        ]
      }

      WorkflowTemplate.on_message_received(socket, session)
      assert_received {:found_code, "name: Last\njobs: []"}
    end
  end
end
