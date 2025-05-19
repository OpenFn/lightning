defmodule LightningWeb.Live.AiAssistant.Modes.JobCode do
  @moduledoc """
  Implementation of the ModeBehavior protocol for job code assistance.

  This module provides functionality for AI-assisted job code development and debugging.
  It implements the `ModeBehavior` protocol to handle job-specific operations like
  session creation, message handling, and code assistance.

  ## Features
  * Creates job-specific chat sessions
  * Handles user messages and AI responses
  * Provides code assistance and debugging help
  * Manages job-specific context including adaptor and expression
  """

  @behaviour LightningWeb.Live.AiAssistant.ModeBehavior

  require Phoenix.LiveView
  alias Lightning.AiAssistant
  require Logger

  @doc """
  Creates a new chat session for job code assistance.

  ## Parameters
    * assigns - A map containing:
      * selected_job - The job to get assistance for
      * current_user - The user creating the session
    * content - The initial message content for the session

  ## Returns
    * `{:ok, session}` - The session was created successfully
    * `{:error, reason}` - The session creation failed

  ## Example
      iex> create_session(%{selected_job: job, current_user: user}, "Help with this job")
      {:ok, %ChatSession{...}}
  """
  @impl true
  def create_session(%{selected_job: job, current_user: user}, content) do
    case AiAssistant.create_session(job, user, content) do
      {:ok, session} -> {:ok, session}
      error -> error
    end
  end

  @doc """
  Retrieves and prepares a job session with its context.

  This function not only retrieves the session but also prepares it with the job's
  expression and adaptor information for proper context in the AI assistance.

  ## Parameters
    * session_id - The ID of the session to retrieve
    * assigns - A map containing:
      * selected_job - The job to get context from

  ## Returns
    * `session` - The retrieved and prepared chat session

  ## Example
      iex> get_session!("session_123", %{selected_job: job})
      %ChatSession{...}
  """
  @impl true
  def get_session!(session_id, %{selected_job: job}) do
    AiAssistant.get_session!(session_id)
    |> AiAssistant.put_expression_and_adaptor(job.body, job.adaptor)
  end

  @doc """
  Saves a user message to the job session.

  ## Parameters
    * socket - The LiveView socket containing:
      * session - The current chat session
      * current_user - The user sending the message
    * content - The message content to save

  ## Returns
    * `{:ok, session}` - The message was saved successfully
    * `{:error, reason}` - The message save failed

  ## Example
      iex> save_message(socket, "How do I fix this error?")
      {:ok, %ChatSession{...}}
  """
  @impl true
  def save_message(%{session: session, current_user: user}, content) do
    AiAssistant.save_message(session, %{
      role: :user,
      content: content,
      user: user
    })
  end

  @doc """
  Processes a message through the job code assistance AI.

  ## Parameters
    * session - The current chat session
    * content - The message content to process

  ## Returns
    * `{:ok, session}` - The message was processed successfully
    * `{:error, reason}` - The message processing failed

  ## Example
      iex> query(session, "How do I transform this data?")
      {:ok, %ChatSession{...}}
  """
  @impl true
  def query(session, content) do
    AiAssistant.query(session, content)
  end

  @impl true
  def chat_input_disabled?(%{
        selected_job: selected_job,
        can_edit_workflow: can_edit_workflow,
        ai_limit_result: ai_limit_result,
        endpoint_available?: endpoint_available?,
        pending_message: pending_message
      }) do
    !can_edit_workflow or
      has_reached_limit?(ai_limit_result) or
      !endpoint_available? or
      !is_nil(pending_message.loading) or job_is_unsaved?(selected_job)
  end

  def disabled_tooltip_message(%{
        can_edit_workflow: can_edit_workflow,
        ai_limit_result: ai_limit_result,
        selected_job: selected_job
      }) do
    case {can_edit_workflow, ai_limit_result, selected_job} do
      {false, _, _} ->
        "You are not authorized to use the Ai Assistant"

      {_, {:error, _reason, _msg} = error, _} ->
        error_message(error)

      {_, _, %{__meta__: %{state: :built}}} ->
        "Save the job first in order to use the AI Assistant"

      _ ->
        nil
    end
  end

  def error_message({:error, message}) when is_binary(message) do
    message
  end

  def error_message({:error, %Ecto.Changeset{}}) do
    "Could not save message. Please try again."
  end

  def error_message({:error, _reason, %{text: text_message}}) do
    text_message
  end

  def error_message(_error) do
    "Oops! Something went wrong. Please try again."
  end

  defp has_reached_limit?(ai_limit_result) do
    ai_limit_result != :ok
  end

  defp job_is_unsaved?(%{__meta__: %{state: :built}} = _job) do
    true
  end

  defp job_is_unsaved?(_job), do: false
end
