defmodule LightningWeb.Live.AiAssistant.Modes.WorkflowTemplate do
  @moduledoc """
  Implementation of the ModeBehavior protocol for workflow template generation.

  This module provides functionality for generating and managing workflow templates
  through the AI Assistant. It implements the `ModeBehavior` protocol to handle
  workflow-specific operations like session creation, message handling, and
  template generation.

  ## Features
  * Creates workflow-specific chat sessions
  * Handles user messages and AI responses
  * Generates workflow templates in YAML format
  * Manages workflow-specific context and state
  """

  @behaviour LightningWeb.Live.AiAssistant.ModeBehavior

  require Phoenix.LiveView
  alias Lightning.AiAssistant

  @doc """
  Creates a new chat session for workflow template generation.

  ## Parameters
    * assigns - A map containing:
      * selected_project - The project to generate templates for
      * current_user - The user creating the session
    * content - The initial message content for the session

  ## Returns
    * `{:ok, session}` - The session was created successfully
    * `{:error, reason}` - The session creation failed

  ## Example
      iex> create_session(%{selected_project: project, current_user: user}, "Create a workflow")
      {:ok, %ChatSession{...}}
  """
  @impl true
  def create_session(
        %{project: project, current_user: current_user},
        content
      ) do
    AiAssistant.create_workflow_session(project, current_user, content)
  end

  @doc """
  Retrieves a workflow session by ID.

  ## Parameters
    * session_id - The ID of the session to retrieve
    * _assigns - Unused in this implementation

  ## Returns
    * `session` - The retrieved chat session

  ## Example
      iex> get_session!("session_123", %{})
      %ChatSession{...}
  """
  @impl true
  def get_session!(session_id, _assigns) do
    AiAssistant.get_session!(session_id)
  end

  @doc """
  Saves a user message to the workflow session.

  ## Parameters
    * assigns - A map containing:
      * session - The current chat session
      * current_user - The user sending the message
    * content - The message content to save

  ## Returns
    * `{:ok, session}` - The message was saved successfully
    * `{:error, reason}` - The message save failed

  ## Example
      iex> save_message(%{session: session, current_user: user}, "Add a trigger")
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
  Processes a message through the workflow template generation AI.

  ## Parameters
    * session - The current chat session
    * content - The message content to process

  ## Returns
    * `{:ok, session}` - The message was processed successfully
    * `{:error, reason}` - The message processing failed

  ## Example
      iex> query(session, "Create a workflow with HTTP trigger")
      {:ok, %ChatSession{...}}
  """
  @impl true
  def query(session, content) do
    AiAssistant.query_workflow(session, content)
  end
end
