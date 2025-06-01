defmodule LightningWeb.Live.AiAssistant.ErrorHandler do
  @moduledoc """
  Comprehensive error handling and message formatting for AI Assistant interactions.

  This module provides a centralized, consistent approach to error handling across
  all AI Assistant modes and operations. It transforms technical errors into
  user-friendly messages that provide clear guidance and actionable feedback.
  """

  @doc """
  Transforms various error types into user-friendly, actionable messages.

  This is the primary error formatting function that handles the most common
  error scenarios across the AI Assistant system. It provides intelligent
  error detection and appropriate message formatting for different error types.

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
      when is_binary(text_message) and text_message != "",
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
  """
  @spec format_limit_error(any()) :: String.t()
  def format_limit_error({:error, _reason, %{text: text_message}})
      when is_binary(text_message) and text_message != "",
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
  Extracts and formats validation errors from Ecto changesets.
  Processes Ecto changeset validation errors into user-friendly messages
  suitable for form display and user guidance. Handles field name
  humanization, error message interpolation, and multiple error aggregation.

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
  """
  @spec extract_changeset_errors(Ecto.Changeset.t()) :: [String.t()]
  def extract_changeset_errors(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.filter(fn {_field, {message, _opts}} -> message != "" end)
    |> Enum.map(fn {field, {message, opts}} ->
      field_name =
        field |> to_string() |> String.replace("_", " ") |> String.capitalize()

      interpolated_message = interpolate_error_message(message, opts)
      "#{field_name} #{interpolated_message}"
    end)
    |> Enum.filter(&(&1 != ""))
  end

  def extract_changeset_errors(_), do: []

  defp interpolate_error_message(message, opts) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", inspect(value))
    end)
  end
end
