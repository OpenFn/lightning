defmodule LightningWeb.Live.AiAssistant.Modes.WorkflowTemplate do
  @moduledoc """
  AI Assistant mode for intelligent workflow template generation and management.

  This mode leverages advanced AI capabilities to transform natural language descriptions
  into complete, production-ready Lightning workflow templates. It provides an intuitive
  interface for creating complex data integration workflows without requiring deep
  technical knowledge of Lightning's YAML structure.

  ## Key Features

  ### Intelligent Template Generation
  - **Natural language processing** - Converts descriptions into structured workflows
  - **Complete YAML generation** - Produces valid Lightning workflow definitions
  - **Multi-step workflow support** - Handles complex data transformation pipelines
  - **Best practices integration** - Applies Lightning conventions and patterns

  ### Advanced Workflow Capabilities
  - **Adaptor selection** - Intelligently chooses appropriate OpenFn adaptors
  - **Trigger configuration** - Sets up cron schedules and webhook triggers
  - **Data flow modeling** - Maps input sources to output destinations
  - **Error handling patterns** - Includes robust error management strategies

  ### Iterative Improvement
  - **Template refinement** - Allows modification of existing workflows
  - **Validation error fixing** - Helps resolve YAML validation issues
  - **Feature enhancement** - Adds new capabilities to existing templates
  - **Performance optimization** - Suggests improvements for efficiency

  ## Usage Scenarios

  ### Initial Workflow Creation
  ```
  "Create a daily sync from Salesforce to PostgreSQL that:
   - Fetches new contacts created in the last 24 hours
   - Transforms the data to match our database schema
   - Handles API rate limits gracefully
   - Sends error notifications to Slack"
  ```

  ### Template Enhancement
  ```
  "Add retry logic to the HTTP requests and include data validation
   before inserting into the database"
  ```

  ### Error Resolution
  ```
  "Fix the validation error about the invalid cron expression
   and make the sync run every 6 hours instead of daily"
  ```

  ## Workflow Generation Process

  1. **Requirements Analysis** - AI analyzes the natural language description
  2. **Architecture Design** - Determines optimal workflow structure and components
  3. **Adaptor Selection** - Chooses appropriate OpenFn adaptors for integrations
  4. **YAML Generation** - Creates complete, valid Lightning workflow definition
  5. **Validation & Optimization** - Ensures compliance and applies best practices
  6. **Documentation Generation** - Provides explanations and usage guidance

  ## Integration Points

  ### Lightning Core Integration
  - Project-scoped template generation
  - Lightning workflow validation
  - OpenFn adaptor registry integration
  - Lightning permission system compliance

  ### UI Integration
  - Real-time template preview
  - Apply template functionality
  - Validation error display
  - Template export capabilities

  ## Security & Governance

  - **Permission enforcement** - Respects workflow editing permissions
  - **Project isolation** - Templates scoped to specific projects
  - **Usage limit compliance** - Tracks and enforces AI usage quotas
  - **Data protection** - Secure handling of sensitive configuration data

  ## Template Quality Assurance

  - **Syntax validation** - Ensures valid YAML structure
  - **Lightning compliance** - Follows Lightning workflow specifications
  - **Best practice application** - Implements recommended patterns
  - **Performance optimization** - Optimizes for efficiency and reliability
  """

  use LightningWeb.Live.AiAssistant.ModeBehavior

  alias Lightning.AiAssistant
  alias LightningWeb.Live.AiAssistant.ErrorHandler

  @doc """
  Creates a new workflow template generation session.

  Initializes a project-scoped session for AI-powered workflow creation.
  The session is configured for template generation with appropriate
  metadata and context for the AI service.

  ## Required Assigns

  - `:project` - The project where the workflow will be created
  - `:current_user` - The user requesting template generation

  ## Examples

      # Create session for new workflow
      {:ok, session} = WorkflowTemplate.create_session(
        %{project: project, current_user: user},
        "Create a daily Salesforce to PostgreSQL sync workflow"
      )

      # Create session for workflow enhancement
      {:ok, session} = WorkflowTemplate.create_session(
        %{project: project, current_user: user},
        "Add error handling and retry logic to existing webhook workflow"
      )

  ## Implementation Notes

  - Associates session with the target project for proper scoping
  - Sets session type to "workflow_template" for specialized handling
  - Creates initial user message describing the desired workflow
  - Prepares session for template generation workflow
  """
  @impl true
  @spec create_session(map(), String.t()) :: {:ok, map()} | {:error, any()}
  def create_session(%{project: project, current_user: current_user}, content) do
    AiAssistant.create_workflow_session(project, current_user, content)
  end

  @doc """
  Retrieves a workflow template session with full context.

  Loads the complete session including all messages, generated templates,
  and conversation history for template generation continuation.

  ## Examples

      session = WorkflowTemplate.get_session!(session_id, %{})
      # Session includes all messages and any generated workflow YAML

  ## Implementation Notes

  - Loads complete message history for context
  - Includes any previously generated workflow code
  - Prepares session for continued template development
  - No additional context enrichment needed (unlike job mode)
  """
  @impl true
  @spec get_session!(String.t(), map()) :: map()
  def get_session!(session_id, _assigns) do
    AiAssistant.get_session!(session_id)
  end

  @doc """
  Lists workflow template sessions for the current project.

  Retrieves paginated sessions associated with the project, filtered
  to show only workflow template generation conversations.

  ## Required Assigns

  - `:project` - The project to filter sessions by

  ## Examples

      # Load recent template sessions
      %{sessions: sessions, pagination: meta} = WorkflowTemplate.list_sessions(
        %{project: project},
        :desc,
        limit: 15
      )

  ## Implementation Notes

  - Filters to workflow template sessions only
  - Project-scoped for proper isolation
  - Includes session metadata for preview display
  - Supports pagination for performance
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

  ## Required Assigns

  - `:project` - The project to check session count for

  ## Examples

      if WorkflowTemplate.more_sessions?(%{project: project}, 15) do
        # Show "Load More" button
      end
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

  ## Required Assigns

  - `:session` - The target template generation session
  - `:current_user` - The user sending the message

  ## Examples

      # Save template modification request
      {:ok, updated_session} = WorkflowTemplate.save_message(
        %{session: session, current_user: user},
        "Add data validation before database insertion"
      )

      # Save error correction request
      {:ok, updated_session} = WorkflowTemplate.save_message(
        %{session: session, current_user: user},
        "Fix the cron expression to run every 2 hours"
      )
  """
  @impl true
  @spec save_message(map(), String.t()) :: {:ok, map()} | {:error, any()}
  def save_message(%{session: session, current_user: user}, content) do
    AiAssistant.save_message(session, %{
      role: :user,
      content: content,
      user: user
    })
  end

  @doc """
  Processes workflow template requests through the AI service.

  Sends user descriptions and requirements to the specialized workflow
  generation AI service, which returns complete YAML templates and
  explanatory content.

  ## Parameters

  - `session` - Session with conversation history and context
  - `content` - User's workflow description or modification request

  ## Examples

      # Generate new workflow template
      {:ok, updated_session} = WorkflowTemplate.query(
        session,
        "Create a workflow that processes CSV files uploaded to Google Drive"
      )

      # Modify existing template
      {:ok, updated_session} = WorkflowTemplate.query(
        session,
        "Add error notifications to Slack when the sync fails"
      )

  ## AI Processing Features

  - **Template generation** - Creates complete workflow YAML
  - **Iterative improvement** - Modifies existing templates
  - **Error correction** - Fixes validation issues
  - **Best practices** - Applies Lightning conventions
  - **Documentation** - Provides usage explanations

  ## Response Content

  The AI response includes:
  - Human-readable explanation of the generated workflow
  - Complete YAML workflow definition
  - Usage guidance and configuration notes
  - Best practice recommendations
  """
  @impl true
  @spec query(map(), String.t()) :: {:ok, map()} | {:error, any()}
  def query(session, content) do
    AiAssistant.query_workflow(session, content)
  end

  @doc """
  Determines if workflow template input should be disabled.

  Evaluates conditions specific to template generation to ensure the
  feature is only available when appropriate permissions and service
  availability allow it.

  ## Required Assigns

  - `:can_edit_workflow` - User's workflow editing permissions
  - `:ai_limit_result` - Current AI usage limit status
  - `:endpoint_available?` - AI service availability
  - `:pending_message` - Current message processing state

  ## Disabled Conditions

  - User lacks workflow editing permissions
  - AI usage limits have been reached
  - AI service endpoint is unavailable
  - Template generation is currently in progress

  ## Examples

      # Input enabled for template generation
      chat_input_disabled?(%{
        can_edit_workflow: true,
        ai_limit_result: :ok,
        endpoint_available?: true,
        pending_message: %{loading: nil}
      })
      # => false

      # Input disabled due to usage limits
      chat_input_disabled?(%{
        can_edit_workflow: true,
        ai_limit_result: {:error, :limit_exceeded},
        endpoint_available?: true,
        pending_message: %{loading: nil}
      })
      # => true

  ## Implementation Notes

  - No job save state validation needed (unlike job mode)
  - Focuses on permissions and service availability
  - Considers template generation processing state
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

  ## Title Priority

  1. Session's custom title (if set)
  2. "[Project Name] Workflow" (if project name available)
  3. "New Workflow" (fallback)

  ## Examples

      # With custom title
      chat_title(%{title: "Salesforce to PostgreSQL Sync"})
      # => "Salesforce to PostgreSQL Sync"

      # With project context
      chat_title(%{project: %{name: "Customer Data Platform"}})
      # => "Customer Data Platform Workflow"

      # Fallback
      chat_title(%{})
      # => "New Workflow"
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
  Handles post-processing after workflow template generation.

  Detects when the AI has generated workflow YAML code and triggers
  appropriate UI updates to enable template application and preview.

  ## Parameters

  - `assigns` - Current LiveView assigns
  - `session_or_message` - Updated session or new message with potential YAML
  - `ui_callback` - Function for triggering UI updates

  ## Examples

      # When YAML is generated
      handle_response_generated(assigns, session_with_yaml, ui_callback)
      # Triggers :workflow_code_generated event with the YAML content

      # When no YAML is present
      handle_response_generated(assigns, session_without_yaml, ui_callback)
      # No UI update triggered, returns assigns unchanged

  ## Implementation Notes

  - Extracts workflow YAML from the latest AI response
  - Triggers UI callback to enable template application features
  - Enables real-time template preview and validation
  - Supports iterative template improvement workflow
  """
  @impl true
  @spec handle_response_generated(map(), map(), function()) :: map()
  def handle_response_generated(assigns, session_or_message, ui_callback) do
    case extract_workflow_code(session_or_message) do
      nil ->
        assigns

      code ->
        ui_callback.(:workflow_code_generated, code)
        assigns
    end
  end

  @doc """
  Initializes the UI state when starting a new template session.

  Clears any existing template data and prepares the interface for
  new workflow generation.

  ## Parameters

  - `socket` - LiveView socket with current state
  - `ui_callback` - Function for triggering UI updates

  ## Examples

      # Starting new template session
      on_session_start(socket, ui_callback)
      # Triggers :clear_template to reset UI state

  ## Implementation Notes

  - Ensures clean state for new template generation
  - Prevents confusion from previous template data
  - Prepares UI for fresh workflow creation process
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

  ## Examples

      # Permission denied
      disabled_tooltip_message(%{can_edit_workflow: false})
      # => "You are not authorized to use the AI Assistant"

      # Usage limit reached
      disabled_tooltip_message(%{ai_limit_result: {:error, :monthly_limit}})
      # => "Monthly AI usage limit exceeded"

      # Service available
      disabled_tooltip_message(%{can_edit_workflow: true, ai_limit_result: :ok})
      # => nil
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

  ## Examples

      error_message({:error, :service_unavailable})
      # => "AI service is temporarily unavailable. Please try again."

      error_message(%Ecto.Changeset{})
      # => "Template validation failed: [specific field errors]"
  """
  @spec error_message(any()) :: String.t()
  def error_message(error) do
    ErrorHandler.format_error(error)
  end

  defp has_reached_limit?(ai_limit_result) do
    ai_limit_result != :ok
  end

  defp extract_workflow_code(%Lightning.AiAssistant.ChatSession{
         messages: messages
       }) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn message ->
      if has_workflow_code?(message.workflow_code), do: message.workflow_code
    end)
  end

  defp extract_workflow_code(%Lightning.AiAssistant.ChatMessage{
         workflow_code: code
       }) do
    if has_workflow_code?(code), do: code
  end

  defp extract_workflow_code(_), do: nil

  defp has_workflow_code?(code) when is_binary(code), do: code != ""
  defp has_workflow_code?(_), do: false
end
