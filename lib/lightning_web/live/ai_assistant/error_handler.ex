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
