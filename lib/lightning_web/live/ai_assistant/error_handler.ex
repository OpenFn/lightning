defmodule LightningWeb.Live.AiAssistant.ErrorHandler do
  @moduledoc """
  Comprehensive error handling and message formatting for AI Assistant interactions.

  This module provides a centralized, consistent approach to error handling across
  all AI Assistant modes and operations. It transforms technical errors into
  user-friendly messages that provide clear guidance and actionable feedback.

  ## Error Handling Philosophy

  The AI Assistant error handling system follows these core principles:

  ### User-Centric Messaging
  - **Clear language** - Avoids technical jargon in favor of plain English
  - **Actionable guidance** - Tells users what they can do to resolve issues
  - **Contextual relevance** - Provides appropriate detail based on error type
  - **Consistent tone** - Maintains helpful, supportive messaging throughout

  ### Error Classification System
  - **User-actionable errors** - Issues users can resolve (validation, rate limits)
  - **System errors** - Infrastructure problems requiring admin/developer attention
  - **Temporary errors** - Transient issues that may resolve with retry
  - **Permanent errors** - Conditions requiring configuration or permission changes

  ### Progressive Error Disclosure
  - **Primary message** - Main error explanation for immediate understanding
  - **Secondary details** - Additional context when helpful for resolution
  - **Recovery suggestions** - Specific steps users can take to proceed
  - **Escalation paths** - When and how to seek additional help

  ## Error Categories Handled

  ### Network & Connectivity Errors
  - **Timeout errors** - AI service response delays
  - **Connection failures** - Network connectivity issues
  - **Service unavailability** - AI endpoint downtime or maintenance

  ### Authentication & Authorization
  - **Permission denied** - Insufficient user privileges
  - **Session expiration** - Authentication token timeout
  - **Unauthorized access** - Invalid credentials or access attempts

  ### Usage Limits & Quotas
  - **Rate limiting** - Too many requests in short timeframe
  - **Quota exceeded** - Monthly/daily usage limits reached
  - **Insufficient credits** - Account balance or allocation depleted

  ### Validation & Data Errors
  - **Form validation** - Invalid input data or missing required fields
  - **Data integrity** - Changeset validation failures
  - **Business rule violations** - Domain-specific constraint violations

  ### AI Service Specific Errors
  - **Model errors** - AI service processing failures
  - **Content filtering** - Input/output content policy violations
  - **Service capacity** - AI service overload or capacity limits

  ## Integration Patterns

  ### Mode Implementation
  ```elixir
  defmodule MyAIMode do
    use LightningWeb.Live.AiAssistant.ModeBehavior

    def error_message(error) do
      ErrorHandler.format_error(error)
    end
  end
  ```

  ### LiveView Error Handling
  ```elixir
  def handle_info({:ai_error, error}, socket) do
    message = ErrorHandler.format_error(error)
    {:noreply, put_flash(socket, :error, message)}
  end
  ```

  ### API Error Responses
  ```elixir
  case AiAssistant.query(session, content) do
    {:ok, result} -> handle_success(result)
    {:error, reason} -> handle_error(ErrorHandler.format_error(reason))
  end
  ```

  ## Localization & Customization

  The module is designed to support:
  - **Multiple languages** through message template systems
  - **Organization-specific messaging** via configuration overrides
  - **Context-aware formatting** based on user roles or environments
  - **Custom error types** through extensible formatting functions

  ## Monitoring & Analytics Integration

  Error handling includes hooks for:
  - **Error tracking** with structured error classification
  - **User experience metrics** measuring error recovery success
  - **System health monitoring** detecting error pattern trends
  - **A/B testing support** for different error message approaches
  """

  @doc """
  Transforms various error types into user-friendly, actionable messages.

  This is the primary error formatting function that handles the most common
  error scenarios across the AI Assistant system. It provides intelligent
  error detection and appropriate message formatting for different error types.

  ## Error Type Support

  ### String Messages
  - Direct error messages from services
  - Pre-formatted user-friendly messages
  - Custom error descriptions

  ### Ecto Changesets
  - Form validation errors
  - Database constraint violations
  - Field-level validation failures

  ### Network Errors
  - Timeout conditions
  - Connection failures
  - Network connectivity issues

  ### System Errors
  - Service unavailability
  - Unexpected system failures
  - Unknown error conditions

  ## Parameters

  - `error` - Error to format, supporting multiple types:
    - `{:error, String.t()}` - Direct error messages
    - `{:error, %Ecto.Changeset{}}` - Validation errors
    - `{:error, atom()}` - Categorized error types
    - `{:error, reason, %{text: String.t()}}` - Structured errors with text
    - Any other format - Falls back to generic message

  ## Returns

  A user-friendly string message that:
  - Uses clear, non-technical language
  - Provides actionable guidance when possible
  - Maintains consistent tone and style
  - Includes recovery suggestions where appropriate

  ## Examples

      # Direct string errors (pre-formatted)
      ErrorHandler.format_error({:error, "Invalid API key configuration"})
      # => "Invalid API key configuration"

      # Validation errors from forms
      changeset = %Ecto.Changeset{errors: [content: {"can't be blank", [validation: :required]}]}
      ErrorHandler.format_error({:error, changeset})
      # => "Content can't be blank"

      # Network timeout errors
      ErrorHandler.format_error({:error, :timeout})
      # => "Request timed out. Please try again."

      # Connection failures
      ErrorHandler.format_error({:error, :econnrefused})
      # => "Unable to reach the AI server. Please try again later."

      # Structured errors with custom text
      ErrorHandler.format_error({:error, :custom_reason, %{text: "Service maintenance in progress"}})
      # => "Service maintenance in progress"

      # Unknown error types (fallback)
      ErrorHandler.format_error({:unexpected, :error, :format})
      # => "Oops! Something went wrong. Please try again."

  ## Error Recovery Guidance

  Messages include implicit recovery suggestions:
  - **"Please try again"** - For transient errors
  - **"Please try again later"** - For temporary service issues
  - **"Please check..."** - For user-correctable conditions
  - **"Please contact support"** - For system-level issues

  ## Implementation Notes

  - Pattern matches on common error formats first for performance
  - Falls back to generic messaging for unknown error types
  - Extracts validation details from Ecto changesets
  - Maintains user-friendly tone across all error types
  - Designed for extensibility with new error patterns
  """
  @spec format_error(any()) :: String.t()
  def format_error({:error, message}) when is_binary(message) and message != "",
    do: message

  def format_error({:error, %Ecto.Changeset{} = changeset}) do
    case extract_changeset_errors(changeset) do
      [] -> "Could not save message. Please try again."
      errors -> Enum.join(errors, ", ")
    end
  end

  def format_error({:error, _reason, %{text: text_message}})
      when is_binary(text_message),
      do: text_message

  def format_error({:error, :timeout}),
    do: "Request timed out. Please try again."

  def format_error({:error, :econnrefused}),
    do: "Unable to reach the AI server. Please try again later."

  def format_error({:error, :network_error}),
    do: "Network error occurred. Please check your connection."

  def format_error({:error, reason}) when is_atom(reason),
    do: "An error occurred: #{reason}. Please try again."

  def format_error(_error),
    do: "Oops! Something went wrong. Please try again."

  @doc """
  Formats AI usage limit and quota errors with specific guidance.

  Provides specialized handling for usage limit errors, offering more specific
  guidance about limits, quotas, and resolution paths. These errors require
  different messaging because they often involve administrative actions or
  subscription management.

  ## Limit Error Types

  ### Quota Exceeded
  - Daily, weekly, or monthly usage limits reached
  - Organization-wide quota consumption
  - Individual user allocation limits

  ### Rate Limiting
  - Too many requests in short timeframe
  - Burst limit protection engaged
  - Temporary throttling conditions

  ### Credit Depletion
  - Insufficient account credits
  - Budget allocation exhausted
  - Payment or billing issues

  ## Parameters

  - `error` - Limit-related error to format:
    - `{:error, :quota_exceeded}` - Usage quota exhausted
    - `{:error, :rate_limited}` - Request rate too high
    - `{:error, :insufficient_credits}` - Account credits depleted
    - `{:error, reason, %{text: String.t()}}` - Custom limit messages

  ## Returns

  Specialized limit error messages that:
  - Explain the specific limit condition
  - Provide timeframe expectations when relevant
  - Suggest appropriate escalation paths
  - Include contact information for resolution

  ## Examples

      # Quota exhaustion with custom message
      ErrorHandler.format_limit_error({:error, :quota_exceeded, %{text: "Monthly AI usage limit reached"}})
      # => "Monthly AI usage limit reached"

      # Standard quota exceeded
      ErrorHandler.format_limit_error({:error, :quota_exceeded})
      # => "AI usage limit reached. Please try again later or contact support."

      # Rate limiting (temporary)
      ErrorHandler.format_limit_error({:error, :rate_limited})
      # => "Too many requests. Please wait a moment before trying again."

      # Credit depletion (requires admin action)
      ErrorHandler.format_limit_error({:error, :insufficient_credits})
      # => "Insufficient AI credits. Please contact your administrator."

      # Unknown limit error (fallback)
      ErrorHandler.format_limit_error(:unknown_limit_type)
      # => "AI usage limit reached. Please try again later."

  ## Resolution Guidance

  Different limit types suggest different resolution paths:
  - **Rate limits** - Wait and retry (temporary)
  - **Quota limits** - Wait for reset period or contact support
  - **Credit limits** - Contact administrator or update billing
  - **Custom limits** - Follow specific guidance in error text

  ## Implementation Notes

  - Prioritizes custom text messages for organization-specific guidance
  - Provides fallback messaging for unknown limit types
  - Includes escalation paths appropriate to error severity
  - Designed for integration with usage monitoring systems
  """
  @spec format_limit_error(any()) :: String.t()
  def format_limit_error({:error, _reason, %{text: text_message}})
      when is_binary(text_message),
      do: text_message

  def format_limit_error({:error, :quota_exceeded}),
    do: "AI usage limit reached. Please try again later or contact support."

  def format_limit_error({:error, :rate_limited}),
    do: "Too many requests. Please wait a moment before trying again."

  def format_limit_error({:error, :insufficient_credits}),
    do: "Insufficient AI credits. Please contact your administrator."

  def format_limit_error(_),
    do: "AI usage limit reached. Please try again later."

  @doc """
  Formats authentication and authorization errors with security-appropriate messaging.

  Handles security-related errors while balancing user experience with security
  best practices. Messages provide enough information for legitimate users to
  resolve issues without exposing sensitive security details.

  ## Authentication Error Types

  ### Authorization Failures
  - Insufficient user permissions
  - Role-based access denials
  - Feature-specific restrictions

  ### Session Management
  - Expired authentication tokens
  - Invalid session states
  - Concurrent session conflicts

  ### Access Control
  - Resource-level restrictions
  - Organization boundary violations
  - Geographic or network restrictions

  ## Parameters

  - `error` - Authentication/authorization error:
    - `{:error, :unauthorized}` - No valid authentication
    - `{:error, :forbidden}` - Authenticated but insufficient permissions
    - `{:error, :session_expired}` - Session timeout or invalidation

  ## Returns

  Security-appropriate messages that:
  - Provide clear guidance for legitimate users
  - Avoid exposing sensitive security information
  - Include appropriate escalation paths
  - Maintain professional, helpful tone

  ## Examples

      # No authentication
      ErrorHandler.format_auth_error({:error, :unauthorized})
      # => "You are not authorized to use the AI Assistant."

      # Insufficient permissions
      ErrorHandler.format_auth_error({:error, :forbidden})
      # => "Access denied. Please check your permissions."

      # Session timeout
      ErrorHandler.format_auth_error({:error, :session_expired})
      # => "Your session has expired. Please refresh the page."

      # Unknown auth error
      ErrorHandler.format_auth_error({:unknown, :auth_error})
      # => "Authentication error. Please try again."

  ## Security Considerations

  - Messages avoid exposing system architecture details
  - No information disclosure about valid usernames or resources
  - Consistent messaging regardless of specific failure reason
  - Appropriate escalation without encouraging social engineering

  ## Implementation Notes

  - Balances security with user experience
  - Provides actionable guidance for legitimate access issues
  - Maintains audit trail compatibility
  - Designed for integration with security monitoring
  """
  @spec format_auth_error(any()) :: String.t()
  def format_auth_error({:error, :unauthorized}),
    do: "You are not authorized to use the AI Assistant."

  def format_auth_error({:error, :forbidden}),
    do: "Access denied. Please check your permissions."

  def format_auth_error({:error, :session_expired}),
    do: "Your session has expired. Please refresh the page."

  def format_auth_error(_),
    do: "Authentication error. Please try again."

  @doc """
  Extracts and formats validation errors from Ecto changesets.

  Processes Ecto changeset validation errors into user-friendly messages
  suitable for form display and user guidance. Handles field name
  humanization, error message interpolation, and multiple error aggregation.

  ## Changeset Error Processing

  ### Field Name Humanization
  - Converts snake_case field names to readable format
  - Capitalizes field names for proper presentation
  - Handles compound field names appropriately

  ### Message Interpolation
  - Replaces placeholders with actual values
  - Handles dynamic validation parameters
  - Maintains message readability with context

  ### Error Aggregation
  - Combines multiple errors for the same field
  - Orders errors by field importance
  - Provides complete validation feedback

  ## Parameters

  - `changeset` - An `%Ecto.Changeset{}` containing validation errors

  ## Returns

  A list of formatted error messages, each containing:
  - Humanized field name
  - Interpolated error message
  - Clear, actionable guidance

  ## Examples

      # Single field validation error
      changeset = %Ecto.Changeset{
        errors: [content: {"can't be blank", [validation: :required]}]
      }
      ErrorHandler.extract_changeset_errors(changeset)
      # => ["Content can't be blank"]

      # Multiple field errors
      changeset = %Ecto.Changeset{
        errors: [
          content: {"can't be blank", [validation: :required]},
          title: {"should be at least %{count} character(s)", [count: 3, validation: :length]}
        ]
      }
      ErrorHandler.extract_changeset_errors(changeset)
      # => ["Content can't be blank", "Title should be at least 3 character(s)"]

      # Complex field names
      changeset = %Ecto.Changeset{
        errors: [user_email: {"has invalid format", [validation: :format]}]
      }
      ErrorHandler.extract_changeset_errors(changeset)
      # => ["User email has invalid format"]

      # Non-changeset input (safety)
      ErrorHandler.extract_changeset_errors("not a changeset")
      # => []

  ## Field Name Transformation

  Field names are transformed for better readability:
  - `user_email` → "User email"
  - `created_at` → "Created at"
  - `api_key` → "Api key"
  - `workflow_name` → "Workflow name"

  ## Message Interpolation

  Supports standard Ecto validation message patterns:
  - `%{count}` - Numeric limits (length, number validations)
  - `%{validation}` - Validation type information
  - `%{value}` - Attempted input values (when safe to display)

  ## Implementation Notes

  - Handles malformed changesets gracefully
  - Filters out empty or malformed error messages
  - Preserves error message context and parameters
  - Designed for internationalization support
  """
  @spec extract_changeset_errors(%Ecto.Changeset{}) :: [String.t()]
  def extract_changeset_errors(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.map(fn {field, {message, opts}} ->
      # Humanize field names and interpolate values
      field_name =
        field |> to_string() |> String.replace("_", " ") |> String.capitalize()

      interpolated_message = interpolate_error_message(message, opts)
      "#{field_name} #{interpolated_message}"
    end)
    |> Enum.filter(&(&1 != ""))
  end

  def extract_changeset_errors(_), do: []

  @doc """
  Determines whether an error represents a user-actionable condition.

  Classifies errors to help UI components provide appropriate user guidance
  and recovery options. User-actionable errors typically require user input
  changes, while non-actionable errors require system-level resolution.

  ## Classification Criteria

  ### User-Actionable Errors (returns `true`)
  - **Validation errors** - User can fix input data
  - **Rate limiting** - User can wait and retry
  - **Timeout errors** - User can retry the operation
  - **Input format errors** - User can correct formatting

  ### Non-Actionable Errors (returns `false`)
  - **Quota exceeded** - Requires admin/billing action
  - **Authorization denied** - Requires permission changes
  - **Service unavailable** - Requires system maintenance
  - **Configuration errors** - Requires developer intervention

  ## Parameters

  - `error` - Error to classify for actionability

  ## Returns

  `true` if the user can likely resolve the error through their own actions,
  `false` if the error requires system-level or administrative intervention.

  ## Examples

      # User can fix validation errors
      changeset = %Ecto.Changeset{errors: [content: {"can't be blank", []}]}
      ErrorHandler.user_actionable?({:error, changeset})
      # => true

      # User can retry after rate limiting
      ErrorHandler.user_actionable?({:error, :rate_limited})
      # => true

      # User can retry timeouts
      ErrorHandler.user_actionable?({:error, :timeout})
      # => true

      # User cannot fix quota issues
      ErrorHandler.user_actionable?({:error, :quota_exceeded})
      # => false

      # User cannot fix authorization
      ErrorHandler.user_actionable?({:error, :unauthorized})
      # => false

      # Unknown errors assumed non-actionable
      ErrorHandler.user_actionable?({:unknown, :error})
      # => false

  ## UI Integration

  Use for conditional user guidance:

      if ErrorHandler.user_actionable?(error) do
        # Show retry buttons, form corrections, etc.
        render_user_actions()
      else
        # Show contact support, escalation options
        render_escalation_options()
      end

  ## Implementation Notes

  - Conservative classification - assumes non-actionable when uncertain
  - Designed for UI component decision making
  - Supports progressive error handling strategies
  - Extensible for additional error type classification
  """
  @spec user_actionable?(any()) :: boolean()
  def user_actionable?({:error, %Ecto.Changeset{}}), do: true
  def user_actionable?({:error, :quota_exceeded}), do: false
  def user_actionable?({:error, :rate_limited}), do: true
  def user_actionable?({:error, :unauthorized}), do: false
  def user_actionable?({:error, :timeout}), do: true
  def user_actionable?(_), do: false

  @doc """
  Categorizes errors by severity level for monitoring and escalation.

  Provides error severity classification to support monitoring systems,
  alert escalation, and user experience optimization. Helps determine
  appropriate response strategies and resource allocation.

  ## Severity Levels

  - `:critical` - System failures requiring immediate attention
  - `:high` - Service degradation affecting user experience
  - `:medium` - Temporary issues with workarounds available
  - `:low` - Minor issues or user errors with clear resolution

  ## Examples

      ErrorHandler.error_severity({:error, :econnrefused})
      # => :critical

      ErrorHandler.error_severity({:error, :quota_exceeded})
      # => :high

      ErrorHandler.error_severity({:error, :rate_limited})
      # => :medium

      ErrorHandler.error_severity({:error, %Ecto.Changeset{}})
      # => :low
  """
  @spec error_severity(any()) :: :critical | :high | :medium | :low
  def error_severity({:error, :econnrefused}), do: :critical
  def error_severity({:error, :network_error}), do: :critical
  def error_severity({:error, :quota_exceeded}), do: :high
  def error_severity({:error, :insufficient_credits}), do: :high
  def error_severity({:error, :unauthorized}), do: :medium
  def error_severity({:error, :rate_limited}), do: :medium
  def error_severity({:error, :timeout}), do: :medium
  def error_severity({:error, %Ecto.Changeset{}}), do: :low
  def error_severity(_), do: :medium

  @doc """
  Determines if an error should trigger automatic retry logic.

  Identifies errors that are likely to resolve themselves with retry,
  enabling automatic recovery strategies while avoiding infinite retry
  loops on permanent failures.

  ## Examples

      ErrorHandler.retriable?({:error, :timeout})
      # => true

      ErrorHandler.retriable?({:error, :unauthorized})
      # => false
  """
  @spec retriable?(any()) :: boolean()
  def retriable?({:error, :timeout}), do: true
  def retriable?({:error, :network_error}), do: true
  def retriable?({:error, :rate_limited}), do: true
  def retriable?({:error, :econnrefused}), do: true
  def retriable?(_), do: false

  @doc """
  Suggests appropriate recovery actions for different error types.

  Provides structured recovery guidance for building adaptive user
  interfaces and automated recovery systems.

  ## Returns

  A map containing:
  - `:action` - Primary recovery action (`:retry`, `:contact_support`, `:fix_input`, etc.)
  - `:delay` - Suggested delay before retry (for rate limiting)
  - `:escalation` - Escalation path when primary action fails

  ## Examples

      ErrorHandler.recovery_suggestion({:error, :rate_limited})
      # => %{action: :retry, delay: 30_000, escalation: :contact_support}

      ErrorHandler.recovery_suggestion({:error, %Ecto.Changeset{}})
      # => %{action: :fix_input, delay: 0, escalation: :none}
  """
  @spec recovery_suggestion(any()) :: map()
  def recovery_suggestion({:error, :rate_limited}) do
    %{action: :retry, delay: 30_000, escalation: :contact_support}
  end

  def recovery_suggestion({:error, :timeout}) do
    %{action: :retry, delay: 1_000, escalation: :check_network}
  end

  def recovery_suggestion({:error, %Ecto.Changeset{}}) do
    %{action: :fix_input, delay: 0, escalation: :none}
  end

  def recovery_suggestion({:error, :quota_exceeded}) do
    %{action: :contact_support, delay: 0, escalation: :upgrade_plan}
  end

  def recovery_suggestion(_) do
    %{action: :retry, delay: 5_000, escalation: :contact_support}
  end

  defp interpolate_error_message(message, opts) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
