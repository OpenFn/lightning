defmodule LightningWeb.Live.AiAssistant.Modes.WorkflowTemplate do
  @moduledoc """
  AI Assistant mode for intelligent workflow template generation and management.

  This mode leverages advanced AI capabilities to transform natural language descriptions
  into complete, production-ready Lightning workflow templates. It provides an intuitive
  interface for creating complex data integration workflows without requiring deep
  technical knowledge of Lightning's YAML structure.
  """

  use LightningWeb.Live.AiAssistant.ModeBehavior

  alias Lightning.AiAssistant
  alias LightningWeb.Live.AiAssistant.ErrorHandler

  require Logger

  @doc """
  Creates a new workflow template generation session.

  Initializes a project-scoped session for AI-powered workflow creation.
  The session is configured for template generation with appropriate
  metadata and context for the AI service.
  """
  @impl true
  @spec create_session(map(), String.t()) :: {:ok, map()} | {:error, any()}
  def create_session(
        %{
          project: project,
          current_user: current_user
        } = assigns,
        content
      ) do
    AiAssistant.create_workflow_session(project, current_user, content,
      workflow_code: assigns[:workflow_code]
    )
  end

  @doc """
  Retrieves a workflow template session with full context.

  Loads the complete session including all messages, generated templates,
  and conversation history for template generation continuation.
  <<<<<<< HEAD
  =======

  ## Examples

      session = WorkflowTemplate.get_session!(%{chat_session_id: session_id})
      # Session includes all messages and any generated workflow YAML
  >>>>>>> origin/main
  """
  @impl true
  @spec get_session!(map()) :: map()
  def get_session!(%{chat_session_id: session_id}) do
    AiAssistant.get_session!(session_id)
  end

  @doc """
  Lists workflow template sessions for the current project.

  Retrieves paginated sessions associated with the project, filtered
  to show only workflow template generation conversations.
  """
  @impl true
  @spec list_sessions(map(), atom(), keyword()) :: %{
          sessions: [map()],
          pagination: map()
        }
  def list_sessions(%{project: project}, sort_direction, opts \\ []) do
    AiAssistant.list_sessions(project, sort_direction, opts)
  end

  @doc """
  Checks if more workflow template sessions exist for the project.

  Determines if additional sessions are available beyond the current count
  for implementing pagination controls.
  """
  @impl true
  @spec more_sessions?(map(), integer()) :: boolean()
  def more_sessions?(%{project: project}, current_count) do
    AiAssistant.has_more_sessions?(project, current_count)
  end

  @doc """
  Saves a user message to the workflow template session.

  Adds user requests, modifications, or questions to the conversation
  history for AI processing and template generation.
  """
  @impl true
  @spec save_message(map(), String.t()) :: {:ok, map()} | {:error, any()}
  def save_message(
        %{session: session, current_user: user, workflow_code: workflow_code},
        content
      ) do
    AiAssistant.save_message(
      session,
      %{role: :user, content: content, user: user},
      workflow_code: workflow_code
    )
  end

  @doc """
  Processes workflow template requests through the AI service.

  Sends user descriptions and requirements to the specialized workflow
  generation AI service, which returns complete YAML templates and
  explanatory content.

  ## Parameters

  - `session` - Session with conversation history and context
  - `content` - User's workflow description or modification request
  - `opts` - Additional options for AI processing (e.g., workflow YAML, errors, etc.)
  """
  @impl true
  def query(session, content, opts \\ []) do
    AiAssistant.query_workflow(session, content, opts)
  end

  @impl true
  def query_options(%{workflow_code: workflow_code}) do
    [workflow_code: workflow_code]
  end

  @doc """
  Determines if workflow template input should be disabled.

  Evaluates conditions specific to template generation to ensure the
  feature is only available when appropriate permissions and service
  availability allow it.
  """
  @impl true
  @spec chat_input_disabled?(map()) :: boolean()
  def chat_input_disabled?(%{
        can_edit_workflow: can_edit_workflow,
        ai_limit_result: ai_limit_result,
        endpoint_available?: endpoint_available?,
        pending_message: pending_message
      }) do
    !can_edit_workflow or
      has_reached_limit?(ai_limit_result) or
      !endpoint_available? or
      !is_nil(pending_message.loading)
  end

  @doc """
  Provides workflow-specific placeholder text for input guidance.

  Encourages users to describe their desired workflow functionality
  in natural language for AI template generation.
  """
  @impl true
  @spec input_placeholder() :: String.t()
  def input_placeholder do
    "Describe the workflow you want to create..."
  end

  @doc """
  Generates contextual titles for workflow template sessions.

  Creates descriptive titles that include project context when available,
  making it easier to identify and organize template generation sessions.
  """
  @impl true
  @spec chat_title(map()) :: String.t()
  def chat_title(session) do
    case session do
      %{title: title} when is_binary(title) and title != "" ->
        title

      %{project: %{name: project_name}} when is_binary(project_name) ->
        "#{project_name} Workflow"

      _ ->
        "New Workflow"
    end
  end

  @doc """
  Indicates that workflow mode supports template generation.

  This mode's primary purpose is generating workflow templates,
  enabling UI features like template application and export.
  """
  @impl true
  @spec supports_template_generation?() :: boolean()
  def supports_template_generation?, do: true

  @doc """
  Provides metadata for the workflow template generation mode.

  Returns information used by the UI to display mode selection options
  and identify the mode's template generation capabilities.
  """
  @impl true
  @spec metadata() :: map()
  def metadata do
    %{
      name: "Workflow Builder",
      description: "Generate complete workflows from your descriptions",
      icon: "hero-cpu-chip"
    }
  end

  @doc """
  Extracts workflow YAML code from AI-generated responses.

  Searches through the session or message to find any generated workflow
  YAML code that can be applied as a template.

  ## Parameters

  - `session_or_message` - Updated session or new message with potential YAML

  ## Returns

  - `%{yaml: String.t()}` - If workflow YAML was found
  - `nil` - If no workflow code was generated
  """
  @impl true
  @spec extract_generated_code(
          Lightning.AiAssistant.ChatSession.t()
          | Lightning.AiAssistant.ChatMessage.t()
        ) ::
          %{yaml: String.t()} | nil
  def extract_generated_code(session_or_message) do
    case extract_workflow_yaml(session_or_message) do
      nil -> nil
      yaml -> %{yaml: yaml}
    end
  end

  @doc """
  Initializes the UI state when starting a new template session.

  Clears any existing template data and prepares the interface for
  new workflow generation.

  ## Parameters

  - `socket` - LiveView socket with current state
  - `ui_callback` - Function for triggering UI updates
  """
  @impl true
  @spec on_session_start(map(), function()) :: map()
  def on_session_start(socket, ui_callback) do
    ui_callback.(:clear_template, nil)
    socket
  end

  @doc """
  Generates appropriate tooltip messages when template input is disabled.

  Provides specific explanations for why workflow template generation
  is unavailable, helping users understand required actions.

  ## Parameters

  - `assigns` - Map containing permission and limit information

  ## Returns

  String explanation or `nil` if input should be enabled.
  """
  @spec disabled_tooltip_message(map()) :: String.t() | nil
  def disabled_tooltip_message(assigns) do
    case {assigns.can_edit_workflow, assigns.ai_limit_result} do
      {false, _} ->
        "You are not authorized to use the AI Assistant"

      {_, error} when error != :ok ->
        ErrorHandler.format_limit_error(error)

      _ ->
        nil
    end
  end

  @doc """
  Formats errors consistently for workflow template mode.

  Leverages shared error handling to provide user-friendly error messages
  for template generation failures and validation issues.

  ## Parameters

  - `error` - Error to format (changeset, atom, string, etc.)

  ## Returns

  Human-readable error message string.
  """
  @spec error_message(any()) :: String.t()
  def error_message(error) do
    ErrorHandler.format_error(error)
  end

  defp has_reached_limit?(ai_limit_result) do
    ai_limit_result != :ok
  end

  defp extract_workflow_yaml(%Lightning.AiAssistant.ChatSession{
         messages: messages
       }) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn message ->
      if has_workflow_code?(message.workflow_code), do: message.workflow_code
    end)
  end

  defp extract_workflow_yaml(%Lightning.AiAssistant.ChatMessage{
         workflow_code: code
       }) do
    if has_workflow_code?(code), do: code
  end

  defp has_workflow_code?(code) when is_binary(code), do: code != ""
  defp has_workflow_code?(_), do: false
end
