defmodule LightningWeb.AiAssistant.Modes.JobCodeTest do
  use Lightning.DataCase, async: true

  alias LightningWeb.Live.AiAssistant.Modes.JobCode

  describe "chat_input_disabled?/1" do
    test "disables when job is unsaved (state: :built)" do
      assigns = %{
        selected_job: %{__meta__: %{state: :built}},
        can_edit: true,
        ai_limit_result: :ok,
        endpoint_available: true,
        pending_message: %{loading: nil}
      }

      assert JobCode.chat_input_disabled?(assigns) == true
    end

    test "enables when job is saved (state: :loaded)" do
      assigns = %{
        selected_job: %{__meta__: %{state: :loaded}},
        can_edit: true,
        ai_limit_result: :ok,
        endpoint_available: true,
        pending_message: %{loading: nil}
      }

      assert JobCode.chat_input_disabled?(assigns) == false
    end

    test "disables when user lacks edit permissions" do
      assigns = %{
        selected_job: %{__meta__: %{state: :loaded}},
        can_edit: false,
        ai_limit_result: :ok,
        endpoint_available: true,
        pending_message: %{loading: nil}
      }

      assert JobCode.chat_input_disabled?(assigns) == true
    end

    test "disables when AI limits reached" do
      assigns = %{
        selected_job: %{__meta__: %{state: :loaded}},
        can_edit: true,
        ai_limit_result: {:error, :quota_exceeded},
        endpoint_available: true,
        pending_message: %{loading: nil}
      }

      assert JobCode.chat_input_disabled?(assigns) == true
    end

    test "disables when endpoint unavailable" do
      assigns = %{
        selected_job: %{__meta__: %{state: :loaded}},
        can_edit: true,
        ai_limit_result: :ok,
        endpoint_available: false,
        pending_message: %{loading: nil}
      }

      assert JobCode.chat_input_disabled?(assigns) == true
    end

    test "disables when message is pending" do
      assigns = %{
        selected_job: %{__meta__: %{state: :loaded}},
        can_edit: true,
        ai_limit_result: :ok,
        endpoint_available: true,
        pending_message: %{loading: "processing"}
      }

      assert JobCode.chat_input_disabled?(assigns) == true
    end
  end

  describe "input_placeholder/0" do
    test "returns job-specific placeholder" do
      assert JobCode.input_placeholder() ==
               "Ask about your job code, debugging, or OpenFn adaptors..."
    end
  end

  describe "chat_title/1" do
    test "uses custom title when available" do
      session = %{title: "Debug HTTP 401 error"}
      assert JobCode.chat_title(session) == "Debug HTTP 401 error"
    end

    test "uses job name when available" do
      session = %{job: %{name: "Fetch Salesforce Data"}}
      assert JobCode.chat_title(session) == "Help with Fetch Salesforce Data"
    end

    test "falls back to default title" do
      session = %{}
      assert JobCode.chat_title(session) == "Job Code Help"
    end

    test "prefers custom title over job name" do
      session = %{
        title: "Custom Debug Session",
        job: %{name: "Some Job"}
      }

      assert JobCode.chat_title(session) == "Custom Debug Session"
    end

    test "handles empty title gracefully" do
      session = %{title: "", job: %{name: "Test Job"}}
      assert JobCode.chat_title(session) == "Help with Test Job"
    end

    test "handles empty job name gracefully" do
      session = %{job: %{name: ""}}
      assert JobCode.chat_title(session) == "Job Code Help"
    end
  end

  describe "metadata/0" do
    test "returns correct metadata" do
      meta = JobCode.metadata()

      assert meta.name == "Job Code Assistant"

      assert meta.description ==
               "Get help with job code, debugging, and OpenFn adaptors"

      assert meta.icon == "hero-cpu-chip"
    end
  end

  describe "disabled_tooltip_message/1" do
    test "returns permission message when user cannot edit" do
      assigns = %{
        can_edit: false,
        ai_limit_result: :ok,
        selected_job: %{__meta__: %{state: :loaded}}
      }

      message = JobCode.disabled_tooltip_message(assigns)

      assert message == "You are not authorized to use the AI Assistant"
    end

    test "returns limit message when AI limits exceeded" do
      assigns = %{
        can_edit: true,
        ai_limit_result: {:error, :quota_exceeded},
        selected_job: %{__meta__: %{state: :loaded}}
      }

      message = JobCode.disabled_tooltip_message(assigns)

      assert is_binary(message)
      assert String.contains?(message, "limit")
    end

    test "returns save message when job is unsaved" do
      assigns = %{
        can_edit: true,
        ai_limit_result: :ok,
        selected_job: %{__meta__: %{state: :built}}
      }

      message = JobCode.disabled_tooltip_message(assigns)

      assert message == "Save your workflow first to use the AI Assistant"
    end

    test "returns nil when input should be enabled" do
      assigns = %{
        can_edit: true,
        ai_limit_result: :ok,
        selected_job: %{__meta__: %{state: :loaded}}
      }

      message = JobCode.disabled_tooltip_message(assigns)

      assert message == nil
    end
  end

  describe "error_message/1" do
    test "formats errors using ErrorHandler" do
      error = {:error, "Job compilation failed"}

      message = JobCode.error_message(error)

      assert message == "Job compilation failed"
    end
  end

  describe "job_is_unsaved? (via chat_input_disabled?)" do
    test "detects unsaved jobs" do
      assigns_unsaved = %{
        selected_job: %{__meta__: %{state: :built}},
        can_edit: true,
        ai_limit_result: :ok,
        endpoint_available: true,
        pending_message: %{loading: nil}
      }

      assigns_saved = %{
        selected_job: %{__meta__: %{state: :loaded}},
        can_edit: true,
        ai_limit_result: :ok,
        endpoint_available: true,
        pending_message: %{loading: nil}
      }

      assert JobCode.chat_input_disabled?(assigns_unsaved) == true
      assert JobCode.chat_input_disabled?(assigns_saved) == false
    end
  end

  describe "has_reached_limit? (via chat_input_disabled?)" do
    test "detects limit conditions" do
      assigns_limited = %{
        selected_job: %{__meta__: %{state: :loaded}},
        can_edit: true,
        ai_limit_result: {:error, :rate_limited},
        endpoint_available: true,
        pending_message: %{loading: nil}
      }

      assigns_ok = %{
        selected_job: %{__meta__: %{state: :loaded}},
        can_edit: true,
        ai_limit_result: :ok,
        endpoint_available: true,
        pending_message: %{loading: nil}
      }

      assert JobCode.chat_input_disabled?(assigns_limited) == true
      assert JobCode.chat_input_disabled?(assigns_ok) == false
    end
  end
end
