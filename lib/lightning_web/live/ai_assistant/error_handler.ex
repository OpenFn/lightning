defmodule LightningWeb.Live.AiAssistant.ErrorHandler do
  @moduledoc """
  Shared error handling utilities for AI Assistant modes.

  Provides consistent error message formatting across all AI Assistant handlers
  to ensure users get helpful, actionable feedback.
  """

  @doc """
  Formats various error types into user-friendly messages.

  ## Parameters
    * error - The error to format (various types supported)

  ## Returns
    * `String.t()` - A user-friendly error message

  ## Examples
      iex> format_error({:error, "Custom error"})
      "Custom error"

      iex> format_error({:error, %Ecto.Changeset{}})
      "Could not save message. Please try again."

      iex> format_error(:some_unknown_error)
      "Oops! Something went wrong. Please try again."
  """
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
  Formats limit-related error messages with more specific guidance.

  ## Parameters
    * error - The limit error to format

  ## Returns
    * `String.t()` - A user-friendly limit error message

  ## Examples
      iex> format_limit_error({:error, :quota_exceeded, %{text: "Daily limit reached"}})
      "Daily limit reached"

      iex> format_limit_error(:unknown_limit_error)
      "AI usage limit reached. Please try again later."
  """
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
  Formats authentication/authorization errors.

  ## Parameters
    * error - The auth error to format

  ## Returns
    * `String.t()` - A user-friendly auth error message
  """
  def format_auth_error({:error, :unauthorized}),
    do: "You are not authorized to use the AI Assistant."

  def format_auth_error({:error, :forbidden}),
    do: "Access denied. Please check your permissions."

  def format_auth_error({:error, :session_expired}),
    do: "Your session has expired. Please refresh the page."

  def format_auth_error(_),
    do: "Authentication error. Please try again."

  @doc """
  Formats validation errors with field-specific messages.

  ## Parameters
    * changeset - An Ecto changeset with validation errors

  ## Returns
    * `[String.t()]` - List of user-friendly validation error messages
  """
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
  Determines if an error is user-actionable (vs system error).

  ## Parameters
    * error - The error to check

  ## Returns
    * `boolean()` - true if user can likely fix this error
  """
  def user_actionable?({:error, %Ecto.Changeset{}}), do: true
  def user_actionable?({:error, :quota_exceeded}), do: false
  def user_actionable?({:error, :rate_limited}), do: true
  def user_actionable?({:error, :unauthorized}), do: false
  def user_actionable?({:error, :timeout}), do: true
  def user_actionable?(_), do: false

  defp interpolate_error_message(message, opts) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
