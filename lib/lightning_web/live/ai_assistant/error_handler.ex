defmodule LightningWeb.Live.AiAssistant.ErrorHandler do
  @moduledoc """
  Error handling for AI Assistant interactions.

  Transforms technical errors into user-friendly messages.
  """

  @doc """
  Formats errors into user-friendly messages.

  ## Examples

      iex> format_error({:error, "Something went wrong"})
      "Something went wrong"

      iex> format_error({:error, :timeout})
      "Request timed out. Please try again."

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
  Formats AI usage limit errors.

  ## Examples

      iex> format_limit_error({:error, :quota_exceeded})
      "AI usage limit reached. Please try again later or contact support."

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
  Extracts errors from Ecto changesets.
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

  @doc false
  @spec interpolate_error_message(String.t(), Keyword.t()) :: String.t()
  defp interpolate_error_message(message, opts) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", inspect(value))
    end)
  end
end
