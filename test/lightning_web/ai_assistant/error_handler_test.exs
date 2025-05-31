defmodule LightningWeb.AiAssistant.ErrorHandlerTest do
  use ExUnit.Case, async: true

  alias LightningWeb.Live.AiAssistant.ErrorHandler

  describe "format_error/1" do
    test "formats direct string errors" do
      assert ErrorHandler.format_error({:error, "Something went wrong"}) ==
               "Something went wrong"

      assert ErrorHandler.format_error({:error, "Network timeout occurred"}) ==
               "Network timeout occurred"
    end

    test "handles empty string errors" do
      assert ErrorHandler.format_error({:error, ""}) ==
               "Oops! Something went wrong. Please try again."
    end

    test "formats Ecto changeset errors" do
      changeset = %Ecto.Changeset{
        errors: [
          content: {"can't be blank", [validation: :required]},
          title:
            {"should be at least %{count} character(s)",
             [count: 3, validation: :length]}
        ]
      }

      result = ErrorHandler.format_error({:error, changeset})

      assert result ==
               "Content can't be blank, Title should be at least 3 character(s)"
    end

    test "formats single changeset error" do
      changeset = %Ecto.Changeset{
        errors: [content: {"can't be blank", [validation: :required]}]
      }

      result = ErrorHandler.format_error({:error, changeset})
      assert result == "Content can't be blank"
    end

    test "handles empty changeset errors" do
      changeset = %Ecto.Changeset{errors: []}

      result = ErrorHandler.format_error({:error, changeset})
      assert result == "Could not save message. Please try again."
    end

    test "handles malformed changeset errors" do
      changeset = %Ecto.Changeset{
        errors: [invalid_field: {"malformed", []}]
      }

      result = ErrorHandler.format_error({:error, changeset})
      assert result == "Invalid field malformed"
    end

    test "formats structured errors with text field" do
      error =
        {:error, :custom_reason, %{text: "Service maintenance in progress"}}

      result = ErrorHandler.format_error(error)
      assert result == "Service maintenance in progress"
    end

    test "handles structured errors with empty text" do
      error = {:error, :custom_reason, %{text: ""}}
      result = ErrorHandler.format_error(error)
      assert result == "Oops! Something went wrong. Please try again."
    end

    test "formats network timeout errors" do
      result = ErrorHandler.format_error({:error, :timeout})
      assert result == "Request timed out. Please try again."
    end

    test "formats connection refused errors" do
      result = ErrorHandler.format_error({:error, :econnrefused})
      assert result == "Unable to reach the AI server. Please try again later."
    end

    test "formats network errors" do
      result = ErrorHandler.format_error({:error, :network_error})
      assert result == "Network error occurred. Please check your connection."
    end

    test "formats unknown atom errors" do
      result = ErrorHandler.format_error({:error, :unknown_error})
      assert result == "An error occurred: unknown_error. Please try again."
    end

    test "handles unexpected error formats" do
      assert ErrorHandler.format_error({:unexpected, :format}) ==
               "Oops! Something went wrong. Please try again."

      assert ErrorHandler.format_error("plain string") ==
               "Oops! Something went wrong. Please try again."

      assert ErrorHandler.format_error(nil) ==
               "Oops! Something went wrong. Please try again."

      assert ErrorHandler.format_error(%{random: "map"}) ==
               "Oops! Something went wrong. Please try again."
    end
  end

  describe "format_limit_error/1" do
    test "formats structured limit errors with text" do
      error =
        {:error, :quota_exceeded, %{text: "Monthly AI usage limit reached"}}

      result = ErrorHandler.format_limit_error(error)
      assert result == "Monthly AI usage limit reached"
    end

    test "handles structured limit errors with empty text" do
      error = {:error, :quota_exceeded, %{text: ""}}
      result = ErrorHandler.format_limit_error(error)
      assert result == "AI usage limit reached. Please try again later."
    end

    test "formats quota exceeded errors" do
      result = ErrorHandler.format_limit_error({:error, :quota_exceeded})

      assert result ==
               "AI usage limit reached. Please try again later or contact support."
    end

    test "formats rate limited errors" do
      result = ErrorHandler.format_limit_error({:error, :rate_limited})

      assert result ==
               "Too many requests. Please wait a moment before trying again."
    end

    test "formats insufficient credits errors" do
      result = ErrorHandler.format_limit_error({:error, :insufficient_credits})

      assert result ==
               "Insufficient AI credits. Please contact your administrator."
    end

    test "handles unknown limit errors" do
      assert ErrorHandler.format_limit_error({:error, :unknown_limit}) ==
               "AI usage limit reached. Please try again later."

      assert ErrorHandler.format_limit_error(:invalid_format) ==
               "AI usage limit reached. Please try again later."

      assert ErrorHandler.format_limit_error(nil) ==
               "AI usage limit reached. Please try again later."
    end
  end

  describe "format_auth_error/1" do
    test "formats unauthorized errors" do
      result = ErrorHandler.format_auth_error({:error, :unauthorized})
      assert result == "You are not authorized to use the AI Assistant."
    end

    test "formats forbidden errors" do
      result = ErrorHandler.format_auth_error({:error, :forbidden})
      assert result == "Access denied. Please check your permissions."
    end

    test "formats session expired errors" do
      result = ErrorHandler.format_auth_error({:error, :session_expired})
      assert result == "Your session has expired. Please refresh the page."
    end

    test "handles unknown auth errors" do
      assert ErrorHandler.format_auth_error({:error, :unknown_auth_error}) ==
               "Authentication error. Please try again."

      assert ErrorHandler.format_auth_error(:invalid_format) ==
               "Authentication error. Please try again."

      assert ErrorHandler.format_auth_error(nil) ==
               "Authentication error. Please try again."
    end
  end

  describe "extract_changeset_errors/1" do
    test "extracts single field error" do
      changeset = %Ecto.Changeset{
        errors: [content: {"can't be blank", [validation: :required]}]
      }

      result = ErrorHandler.extract_changeset_errors(changeset)
      assert result == ["Content can't be blank"]
    end

    test "extracts multiple field errors" do
      changeset = %Ecto.Changeset{
        errors: [
          content: {"can't be blank", [validation: :required]},
          email: {"has invalid format", [validation: :format]}
        ]
      }

      result = ErrorHandler.extract_changeset_errors(changeset)
      assert "Content can't be blank" in result
      assert "Email has invalid format" in result
      assert length(result) == 2
    end

    test "handles complex field names" do
      changeset = %Ecto.Changeset{
        errors: [
          user_email: {"has invalid format", [validation: :format]},
          workflow_name: {"should be at least %{count} character(s)", [count: 3]}
        ]
      }

      result = ErrorHandler.extract_changeset_errors(changeset)
      assert "User email has invalid format" in result
      assert "Workflow name should be at least 3 character(s)" in result
    end

    test "interpolates error message parameters" do
      changeset = %Ecto.Changeset{
        errors: [
          title:
            {"should be at least %{count} character(s)",
             [count: 5, validation: :length]},
          age:
            {"must be greater than %{number}", [number: 18, validation: :number]}
        ]
      }

      result = ErrorHandler.extract_changeset_errors(changeset)
      assert "Title should be at least 5 character(s)" in result
      assert "Age must be greater than 18" in result
    end

    test "handles errors without interpolation parameters" do
      changeset = %Ecto.Changeset{
        errors: [
          email: {"is invalid", []},
          password: {"confirmation does not match", []}
        ]
      }

      result = ErrorHandler.extract_changeset_errors(changeset)
      assert "Email is invalid" in result
      assert "Password confirmation does not match" in result
    end

    test "filters out empty error messages" do
      changeset = %Ecto.Changeset{
        errors: [
          content: {"can't be blank", [validation: :required]},
          empty_field: {"", []}
        ]
      }

      result = ErrorHandler.extract_changeset_errors(changeset)
      assert result == ["Content can't be blank"]
    end

    test "handles non-changeset input" do
      assert ErrorHandler.extract_changeset_errors("not a changeset") == []
      assert ErrorHandler.extract_changeset_errors(nil) == []
      assert ErrorHandler.extract_changeset_errors(%{}) == []
    end

    test "handles changeset with no errors" do
      changeset = %Ecto.Changeset{errors: []}
      result = ErrorHandler.extract_changeset_errors(changeset)
      assert result == []
    end
  end

  describe "user_actionable?/1" do
    test "returns true for validation errors" do
      changeset = %Ecto.Changeset{
        errors: [content: {"can't be blank", [validation: :required]}]
      }

      assert ErrorHandler.user_actionable?({:error, changeset}) == true
    end

    test "returns true for rate limited errors" do
      assert ErrorHandler.user_actionable?({:error, :rate_limited}) == true
    end

    test "returns true for timeout errors" do
      assert ErrorHandler.user_actionable?({:error, :timeout}) == true
    end

    test "returns false for quota exceeded errors" do
      assert ErrorHandler.user_actionable?({:error, :quota_exceeded}) == false
    end

    test "returns false for unauthorized errors" do
      assert ErrorHandler.user_actionable?({:error, :unauthorized}) == false
    end

    test "returns false for unknown errors" do
      assert ErrorHandler.user_actionable?({:error, :unknown_error}) == false
      assert ErrorHandler.user_actionable?(:invalid_format) == false
      assert ErrorHandler.user_actionable?(nil) == false
    end
  end

  describe "error_severity/1" do
    test "returns critical for connection errors" do
      assert ErrorHandler.error_severity({:error, :econnrefused}) == :critical
      assert ErrorHandler.error_severity({:error, :network_error}) == :critical
    end

    test "returns high for quota/credit errors" do
      assert ErrorHandler.error_severity({:error, :quota_exceeded}) == :high

      assert ErrorHandler.error_severity({:error, :insufficient_credits}) ==
               :high
    end

    test "returns medium for auth and rate limit errors" do
      assert ErrorHandler.error_severity({:error, :unauthorized}) == :medium
      assert ErrorHandler.error_severity({:error, :rate_limited}) == :medium
      assert ErrorHandler.error_severity({:error, :timeout}) == :medium
    end

    test "returns low for validation errors" do
      changeset = %Ecto.Changeset{
        errors: [content: {"can't be blank", [validation: :required]}]
      }

      assert ErrorHandler.error_severity({:error, changeset}) == :low
    end

    test "returns medium for unknown errors" do
      assert ErrorHandler.error_severity({:error, :unknown_error}) == :medium
      assert ErrorHandler.error_severity(:invalid_format) == :medium
    end
  end

  describe "retriable?/1" do
    test "returns true for network-related errors" do
      assert ErrorHandler.retriable?({:error, :timeout}) == true
      assert ErrorHandler.retriable?({:error, :network_error}) == true
      assert ErrorHandler.retriable?({:error, :econnrefused}) == true
      assert ErrorHandler.retriable?({:error, :rate_limited}) == true
    end

    test "returns false for non-retriable errors" do
      assert ErrorHandler.retriable?({:error, :unauthorized}) == false
      assert ErrorHandler.retriable?({:error, :quota_exceeded}) == false
      assert ErrorHandler.retriable?({:error, :insufficient_credits}) == false

      changeset = %Ecto.Changeset{
        errors: [content: {"can't be blank", [validation: :required]}]
      }

      assert ErrorHandler.retriable?({:error, changeset}) == false
    end

    test "returns false for unknown errors" do
      assert ErrorHandler.retriable?({:error, :unknown_error}) == false
      assert ErrorHandler.retriable?(:invalid_format) == false
    end
  end

  describe "recovery_suggestion/1" do
    test "suggests retry with delay for rate limited errors" do
      result = ErrorHandler.recovery_suggestion({:error, :rate_limited})

      assert result.action == :retry
      assert result.delay == 30_000
      assert result.escalation == :contact_support
    end

    test "suggests retry with short delay for timeout errors" do
      result = ErrorHandler.recovery_suggestion({:error, :timeout})

      assert result.action == :retry
      assert result.delay == 1_000
      assert result.escalation == :check_network
    end

    test "suggests fix input for validation errors" do
      changeset = %Ecto.Changeset{
        errors: [content: {"can't be blank", [validation: :required]}]
      }

      result = ErrorHandler.recovery_suggestion({:error, changeset})

      assert result.action == :fix_input
      assert result.delay == 0
      assert result.escalation == :none
    end

    test "suggests contact support for quota errors" do
      result = ErrorHandler.recovery_suggestion({:error, :quota_exceeded})

      assert result.action == :contact_support
      assert result.delay == 0
      assert result.escalation == :upgrade_plan
    end

    test "provides default suggestion for unknown errors" do
      result = ErrorHandler.recovery_suggestion({:error, :unknown_error})

      assert result.action == :retry
      assert result.delay == 5_000
      assert result.escalation == :contact_support
    end
  end

  describe "interpolate_error_message/2 (private function behavior)" do
    test "interpolates count parameter in validation errors" do
      changeset = %Ecto.Changeset{
        errors: [title: {"should be at least %{count} character(s)", [count: 5]}]
      }

      result = ErrorHandler.extract_changeset_errors(changeset)
      assert result == ["Title should be at least 5 character(s)"]
    end

    test "interpolates multiple parameters" do
      changeset = %Ecto.Changeset{
        errors: [
          score: {"must be between %{min} and %{max}", [min: 0, max: 100]}
        ]
      }

      result = ErrorHandler.extract_changeset_errors(changeset)
      assert result == ["Score must be between 0 and 100"]
    end

    test "handles non-existent interpolation parameters" do
      changeset = %Ecto.Changeset{
        errors: [field: {"has %{nonexistent} parameter", [count: 5]}]
      }

      result = ErrorHandler.extract_changeset_errors(changeset)
      assert result == ["Field has %{nonexistent} parameter"]
    end

    test "converts non-string values to strings for interpolation" do
      changeset = %Ecto.Changeset{
        errors: [
          number_field: {"must be %{value}", [value: 42]},
          boolean_field: {"is %{flag}", [flag: true]}
        ]
      }

      result = ErrorHandler.extract_changeset_errors(changeset)
      assert "Number field must be 42" in result
      assert "Boolean field is true" in result
    end
  end

  describe "edge cases and error handling" do
    test "handles deeply nested changeset errors" do
      changeset = %Ecto.Changeset{
        errors: [
          "user.profile.name": {"can't be blank", [validation: :required]},
          "settings.preferences.theme": {"is invalid", [validation: :inclusion]}
        ]
      }

      result = ErrorHandler.extract_changeset_errors(changeset)
      assert "User.profile.name can't be blank" in result
      assert "Settings.preferences.theme is invalid" in result
    end

    test "handles special characters in field names" do
      changeset = %Ecto.Changeset{
        errors: [
          field_with_underscores: {"is invalid", []},
          "field-with-dashes": {"is required", []}
        ]
      }

      result = ErrorHandler.extract_changeset_errors(changeset)
      assert "Field with underscores is invalid" in result
      assert "Field-with-dashes is required" in result
    end

    test "handles nil and empty interpolation values" do
      changeset = %Ecto.Changeset{
        errors: [
          nil_field: {"value is %{nil_value}", [nil_value: nil]},
          empty_field: {"value is %{empty_value}", [empty_value: ""]}
        ]
      }

      result = ErrorHandler.extract_changeset_errors(changeset)
      assert "Nil field value is nil" in result
      assert "Empty field value is \"\"" in result
    end

    test "handles errors with complex data structures" do
      changeset = %Ecto.Changeset{
        errors: [
          complex_field:
            {"invalid data: %{data}", [data: %{key: "value", nested: [1, 2, 3]}]}
        ]
      }

      result = ErrorHandler.extract_changeset_errors(changeset)
      # Should convert the map to string representation
      assert length(result) == 1
      assert String.starts_with?(hd(result), "Complex field invalid data:")
    end
  end
end
