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
end
