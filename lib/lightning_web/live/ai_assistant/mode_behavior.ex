defmodule LightningWeb.Live.AiAssistant.ModeBehavior do
  @moduledoc """
  Defines the behavior contract for AI Assistant interaction modes.

  This behaviour enables the AI Assistant to support multiple interaction patterns
  and contexts through a pluggable mode system. Each mode implements specific
  callbacks to handle different types of AI assistance workflows.
  """

  alias LightningWeb.Live.AiAssistant.PaginationMeta

  @doc """
  Creates a new chat session for the specific mode.

  Initializes a new AI conversation with mode-specific context and configuration.
  This is the entry point for starting new AI assistance workflows.

  ## Parameters

  - `assigns` - LiveView assigns containing necessary context:
    - `:current_user` - The user creating the session
    - `:selected_job` - Job context (for job-specific modes)
    - `:project` - Project context (for workflow template modes)
    - Mode-specific context data
  - `content` - Initial message content that starts the conversation

  ## Returns

  - `{:ok, session}` - Session created successfully with initial message
  - `{:error, reason}` - Creation failed due to validation or system errors

  ## Examples

      # Job mode session creation
      {:ok, session} = MyJobMode.create_session(
        %{selected_job: job, current_user: user},
        "Help me debug this HTTP request"
      )

      # Workflow template mode session creation
      {:ok, session} = WorkflowMode.create_session(
        %{project: project, current_user: user},
        "Create a daily Salesforce sync workflow"
      )

  ## Implementation Notes

  - Should validate required context in assigns
  - Must associate session with appropriate resources (job, project, etc.)
  - Should set mode-specific metadata and configuration
  """
  @callback create_session(
              assigns :: map(),
              content :: String.t()
            ) :: {:ok, map()} | {:error, any()}

  @doc """
  Retrieves and prepares a session with mode-specific context.

  Loads an existing session and enriches it with any mode-specific data
  needed for proper AI assistance. This includes loading related resources,
  setting context variables, and preparing the session for interaction.

  ## Parameters

  `assigns` - LiveView assigns containing context for session preparation:
    - `chat_session_id` - UUID of the session to retrieve
    - `:selected_job` - Current job context
    - `:project` - Current project context
    - Mode-specific preparation data

  ## Returns

  A fully prepared session map with:
  - Preloaded messages and user data
  - Mode-specific context (expressions, adaptors, etc.)
  - UI-ready metadata

  ## Examples

      # Retrieve job session with expression context
      session = JobMode.get_session!(%{chat_session_id: session_id, selected_job: job})
      # session now includes job.expression and job.adaptor

      # Retrieve workflow session with project context
      session = WorkflowMode.get_session!(%{chat_session_id: session_id, project: project})

  ## Implementation Notes

  - Should handle session not found errors gracefully
  - Must enrich session with mode-specific context
  - Should preload necessary associations for efficient rendering
  """
  @callback get_session!(assigns :: map()) :: map()

  @doc """
  Lists sessions with pagination and mode-specific filtering.

  Retrieves a paginated list of sessions relevant to the current mode and context.
  Includes metadata for pagination controls and session preview information.

  ## Parameters

  - `assigns` - LiveView assigns containing filtering context:
    - `:selected_job` - Filter sessions for specific job
    - `:project` - Filter sessions for specific project
    - `:current_user` - User-specific session filtering
  - `sort_direction` - Sort order for sessions:
    - `:desc` - Most recent first (default)
    - `:asc` - Oldest first
  - `opts` - Pagination and filtering options:
    - `:offset` - Number of records to skip (default: 0)
    - `:limit` - Maximum records to return (default: 20)
    - `:search` - Optional search term for filtering

  ## Returns

  A map containing:
  - `:sessions` - List of session maps with preview data
  - `:pagination` - `PaginationMeta` struct with navigation info

  ## Examples

      # Load recent sessions for a job
      %{sessions: sessions, pagination: meta} = JobMode.list_sessions(
        %{selected_job: job, current_user: user},
        :desc,
        limit: 10
      )

      # Load sessions with search
      %{sessions: sessions, pagination: meta} = Mode.list_sessions(
        assigns,
        :desc,
        offset: 20, limit: 10, search: "debugging"
      )

  ## Implementation Notes

  - Should respect mode-specific filtering rules
  - Must include message counts for session previews
  - Should optimize queries for large session lists
  """
  @callback list_sessions(
              assigns :: map(),
              sort_direction :: atom(),
              opts :: keyword()
            ) :: %{sessions: [map()], pagination: PaginationMeta.t()}

  @doc """
  Saves a new message to an existing session.

  Adds a user message to the conversation history and prepares it for AI processing.
  Handles message validation, status tracking, and session updates.

  ## Parameters

  - `assigns` - LiveView assigns containing:
    - `:session` - Target session for the message
    - `:current_user` - User sending the message
    - Mode-specific context
  - `content` - Message content to save

  ## Returns

  - `{:ok, session}` - Message saved successfully, returns updated session
  - `{:error, reason}` - Save failed due to validation or system errors

  ## Examples

      # Save user message to job session
      {:ok, updated_session} = JobMode.save_message(
        %{session: session, current_user: user},
        "Can you explain this error message?"
      )

      # Save message with validation
      case Mode.save_message(assigns, message_content) do
        {:ok, session} ->
          # Continue with AI processing
        {:error, changeset} ->
          # Handle validation errors
      end

  ## Implementation Notes

  - Should validate message content and length
  - Must set appropriate message status (pending, etc.)
  - Should update session metadata as needed
  """
  @callback save_message(
              assigns :: map(),
              content :: String.t()
            ) :: {:ok, map()} | {:error, any()}

  @doc """
  Processes a message through the AI assistant for mode-specific assistance.

  Sends the user's message to the appropriate AI service with mode-specific
  context and handles the response. This is where the actual AI interaction
  happens, tailored to the mode's specific use case.

  ## Parameters

  - `session` - Current chat session with full context
  - `content` - User message content to process

  ## Returns

  - `{:ok, session}` - AI processed successfully, returns updated session with response
  - `{:error, reason}` - Processing failed due to AI service or system errors

  ## Examples

      # Job mode AI query with code context
      {:ok, updated_session} = JobMode.query(session, "How do I add error handling?")
      # Uses job expression and adaptor for targeted assistance

      # Workflow mode AI query for template generation
      {:ok, updated_session} = WorkflowMode.query(session, "Add logging to this workflow")
      # Generates updated workflow YAML

  ## Error Handling

      case Mode.query(session, content) do
        {:ok, session} ->
          # AI responded successfully
        {:error, "Request timed out. Please try again."} ->
          # Handle timeout
        {:error, changeset} ->
          # Handle validation errors
      end

  ## Implementation Notes

  - Should use appropriate AI service endpoint (job_chat, workflow_chat)
  - Must include mode-specific context in AI requests
  - Should handle various error types gracefully
  - Must update message statuses appropriately
  """
  @callback query(
              session :: map(),
              content :: String.t(),
              opts :: map()
            ) :: {:ok, map()} | {:error, any()}

  @doc "validates form params"
  @callback validate_form_changeset(map()) :: Ecto.Changeset.t()

  @callback enable_attachment_options_component?() :: boolean()

  @callback query_options(Ecto.Changeset.t()) :: map()

  @doc """
  Determines if the chat input should be disabled based on mode conditions.

  Evaluates mode-specific conditions to determine when users should not be
  able to send new messages. This enables proper UX during loading states,
  error conditions, or when required context is missing.

  ## Parameters

  - `assigns` - LiveView assigns containing state to evaluate:
    - `:session` - Current session state
    - `:loading` - Loading state flags
    - `:selected_job` - Job selection state (for job modes)
    - Mode-specific state variables

  ## Returns

  `true` if chat input should be disabled, `false` otherwise.

  ## Examples

      # Job mode disables input when no job is selected
      defp chat_input_disabled?(%{selected_job: nil}), do: true
      defp chat_input_disabled?(%{loading: true}), do: true
      defp chat_input_disabled?(_), do: false

      # Workflow mode disables during template generation
      defp chat_input_disabled?(%{generating_template: true}), do: true

  ## Implementation Notes

  - Should check for required context availability
  - Must consider loading and error states
  - Should provide clear user feedback when disabled
  """
  @callback chat_input_disabled?(assigns :: map()) :: boolean()

  @doc """
  Checks if additional sessions are available beyond the current count.

  Determines whether there are more sessions to load without fetching them.
  Used for implementing "Load More" UI patterns and infinite scroll.

  ## Parameters

  - `assigns` - LiveView assigns containing context for availability check
  - `current_count` - Number of sessions currently loaded in the UI

  ## Returns

  `true` if more sessions exist, `false` if all sessions are loaded.

  ## Examples

      if Mode.more_sessions?(assigns, length(loaded_sessions)) do
        # Show "Load More" button
      else
        # Hide pagination controls
      end

  ## Implementation Notes

  - Should be efficient and avoid loading actual session data
  - Must respect same filtering as `list_sessions/3`
  - Should handle edge cases gracefully
  """
  @callback more_sessions?(
              assigns :: map(),
              current_count :: integer()
            ) :: boolean()

  @doc """
  Returns the placeholder text for the chat input field.

  Provides mode-specific guidance to users about what they can ask or
  request from the AI assistant.

  ## Returns

  A string to display as placeholder text in the chat input.

  ## Examples

      # Job mode placeholder
      def input_placeholder, do: "Ask about code, debugging, or adaptor usage..."

      # Workflow mode placeholder
      def input_placeholder, do: "Describe the workflow you want to create..."

  ## Default Implementation

  Returns a generic placeholder encouraging users to start a conversation.
  """
  @callback input_placeholder() :: String.t()

  @doc """
  Returns the display title for a chat session.

  Formats session titles for display in session lists and headers.
  Can customize title generation based on mode-specific context.

  ## Parameters

  - `session` - The chat session map

  ## Returns

  A formatted string to display as the session title.

  ## Examples

      # Job mode with job context
      def chat_title(%{title: title, job: %{name: job_name}}) do
        "# {title} (# {job_name})"
      end

      # Workflow mode with workflow context
      def chat_title(%{title: title, workflow: %{name: workflow_name}}) do
        "# {workflow_name}: # {title}"
      end

  ## Default Implementation

  Returns the session's title field, or "Untitled Chat" if empty.
  """
  @callback chat_title(session :: map()) :: String.t()

  @doc """
  Indicates whether this mode supports template or code generation.

  Determines if the mode can generate templates, code, or other artifacts
  that users might want to apply or save. Affects UI elements like
  "Apply Template" buttons.

  ## Returns

  `true` if mode generates templates/code, `false` otherwise.

  ## Examples

      # Workflow template mode supports generation
      def supports_template_generation?, do: true

      # Job assistance mode doesn't generate templates
      def supports_template_generation?, do: false

  ## Default Implementation

  Returns `false` - most modes provide assistance rather than generation.
  """
  @callback supports_template_generation?() :: boolean()

  @doc """
  Returns metadata about this mode for UI display and configuration.

  Provides information used by the UI to display mode options,
  icons, descriptions, and other mode-specific details.

  ## Returns

  A map containing mode metadata:
  - `:name` - Display name for the mode
  - `:description` - Brief description of mode capabilities
  - `:icon` - Icon class for UI display
  - `:category` - Optional grouping category
  - `:features` - Optional list of supported features

  ## Examples

      def metadata do
        %{
          name: "Job Assistant",
          description: "Get help with coding tasks and debugging",
          icon: "hero-code-bracket",
          category: "development",
          features: ["code_help", "debugging", "adaptor_guidance"]
        }
      end

  ## Default Implementation

  Returns basic metadata with generic name, description, and icon.
  """
  @callback metadata() :: map()

  @doc """
  Handles post-processing after the AI generates a response.

  Called after successful AI response generation to allow mode-specific
  handling, UI updates, or additional processing. The ui_callback parameter
  enables triggering LiveView updates.

  ## Parameters

  - `assigns` - Current LiveView assigns
  - `session_or_message` - The updated session or generated message
  - `ui_callback` - Function to call for triggering UI updates

  ## Returns

  Updated assigns map with any mode-specific changes.

  ## Examples

      # Workflow mode processes generated YAML
      def handle_response_generated(assigns, session, ui_callback) do
        if generated_workflow_yaml?(session) do
          ui_callback.(:show_apply_template_button)
        end
        assigns
      end

      # Job mode tracks successful assistance
      def handle_response_generated(assigns, session, ui_callback) do
        track_successful_assistance(session)
        assigns
      end

  ## Default Implementation

  Returns assigns unchanged - no additional processing.
  """
  @callback handle_response_generated(
              assigns :: map(),
              session_or_message :: map(),
              ui_callback :: function()
            ) :: map()

  @doc """
  Called when a new session starts, allows mode-specific initialization.

  Provides an opportunity for modes to perform setup tasks when users
  start new conversations, such as UI initialization, state preparation,
  or welcome message display.

  ## Parameters

  - `socket` - The LiveView socket with current state
  - `ui_callback` - Function for triggering UI updates

  ## Returns

  Updated socket with mode-specific initialization.

  ## Examples

      # Job mode ensures job is selected
      def on_session_start(socket, ui_callback) do
        if is_nil(socket.assigns.selected_job) do
          ui_callback.(:prompt_job_selection)
        end
        socket
      end

      # Workflow mode shows template options
      def on_session_start(socket, ui_callback) do
        ui_callback.(:show_template_suggestions)
        socket
      end

  ## Default Implementation

  Returns socket unchanged - no initialization needed.
  """
  @callback on_session_start(socket :: map(), ui_callback :: function()) :: map()

  @optional_callbacks [
    validate_form_changeset: 1,
    query_options: 1,
    enable_attachment_options_component?: 0,
    input_placeholder: 0,
    chat_title: 1,
    supports_template_generation?: 0,
    metadata: 0,
    handle_response_generated: 3,
    on_session_start: 2
  ]

  @doc """
  Macro for implementing the ModeBehavior with sensible defaults.

  Provides shared functionality and default implementations for optional
  callbacks, allowing modes to focus on their specific requirements.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour LightningWeb.Live.AiAssistant.ModeBehavior

      alias LightningWeb.Live.AiAssistant.ErrorHandler

      @doc """
      Formats errors consistently across all modes.

      ## Parameters

      - `error` - Error to format (changeset, string, atom, etc.)

      ## Returns

      Human-readable error message string.
      """
      @spec error_message(any()) :: String.t()
      def error_message(error), do: ErrorHandler.format_error(error)

      @doc """
      Default placeholder encouraging users to start a conversation.
      """
      def input_placeholder do
        "Open a previous session or send a message to start a new one"
      end

      def validate_form_changeset(params) do
        data = %{content: nil}
        types = %{content: :string}

        {data, types}
        |> Ecto.Changeset.cast(params, Map.keys(types))
      end

      def query_options(_changeset), do: %{}

      def enable_attachment_options_component?, do: false

      @doc """
      Default title formatting using session title or fallback.
      """
      def chat_title(session) do
        case session do
          %{title: title} when is_binary(title) and title != "" -> title
          _ -> "Untitled Chat"
        end
      end

      @doc """
      Default: most modes don't generate templates.
      """
      def supports_template_generation?, do: false

      @doc """
      Default metadata for generic AI assistance.
      """
      def metadata do
        %{
          name: "AI Assistant",
          description: "General AI assistance",
          icon: "hero-cpu-chip"
        }
      end

      @doc """
      Default: no special response handling needed.
      """
      def handle_response_generated(assigns, _session_or_message, _ui_callback) do
        assigns
      end

      @doc """
      Default: no special session start handling needed.
      """
      def on_session_start(socket, _ui_callback), do: socket

      defoverridable input_placeholder: 0,
                     chat_title: 1,
                     supports_template_generation?: 0,
                     metadata: 0,
                     handle_response_generated: 3,
                     on_session_start: 2,
                     error_message: 1,
                     validate_form_changeset: 1,
                     query_options: 1,
                     enable_attachment_options_component?: 0
    end
  end
end
