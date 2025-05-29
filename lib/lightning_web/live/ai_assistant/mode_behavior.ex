defmodule LightningWeb.Live.AiAssistant.ModeBehavior do
  @moduledoc """
  Defines the behavior for AI Assistant modes.
  Each mode must implement these callbacks to handle mode-specific operations.
  """

  alias LightningWeb.Live.AiAssistant.PaginationMeta

  @doc """
  Creates a new chat session for the given mode.

  ## Parameters
    * assigns - A map containing the necessary context for session creation (e.g., selected_job, current_user)
    * content - The initial message content for the session

  ## Returns
    * `{:ok, session}` - The session was created successfully
    * `{:error, reason}` - The session creation failed
  """
  @callback create_session(
              assigns :: map(),
              content :: String.t()
            ) :: {:ok, map()} | {:error, any()}

  @doc """
  Retrieves and prepares a session for the given mode.

  ## Parameters
    * session_id - The ID of the session to retrieve
    * assigns - A map containing the necessary context for session preparation (e.g., selected_job)

  ## Returns
    * `session` - The prepared session with all necessary context
  """
  @callback get_session!(
              session_id :: String.t(),
              assigns :: map()
            ) :: map()

  @doc """
  Lists sessions with pagination metadata.

  ## Parameters
    * assigns - A map containing the necessary context for session listing
    * sort_direction - The direction to sort sessions (:asc or :desc)
    * opts - Optional keyword list for pagination and filtering
      * `:offset` - Number of records to skip (default: 0)
      * `:limit` - Maximum number of records to return (default: 20)

  ## Returns
    * `%{sessions: [session], pagination: PaginationMeta.t()}` - Sessions with pagination info

  ## Examples
      # Load first 20 sessions
      list_sessions(assigns, :desc, limit: 20)

      # Load next 20 sessions
      list_sessions(assigns, :desc, offset: 20, limit: 20)
  """
  @callback list_sessions(
              assigns :: map(),
              sort_direction :: atom(),
              opts :: keyword()
            ) :: %{sessions: [map()], pagination: PaginationMeta.t()}

  @doc """
  Saves a new message to an existing session.

  ## Parameters
    * assigns - A map containing the session and user information
    * content - The message content to save

  ## Returns
    * `{:ok, session}` - The message was saved successfully
    * `{:error, reason}` - The message save failed
  """
  @callback save_message(
              assigns :: map(),
              content :: String.t()
            ) :: {:ok, map()} | {:error, any()}

  @doc """
  Processes a message through the AI assistant for the given mode.

  ## Parameters
    * session - The current chat session
    * content - The message content to process

  ## Returns
    * `{:ok, session}` - The message was processed successfully
    * `{:error, reason}` - The message processing failed
  """
  @callback query(
              session :: map(),
              content :: String.t()
            ) :: {:ok, map()} | {:error, any()}

  @doc """
  Determines if the chat input should be disabled based on mode-specific conditions.

  ## Parameters
    * assigns - A map containing the necessary context for determining disabled state

  ## Returns
    * `boolean()` - Whether the chat input should be disabled
  """
  @callback chat_input_disabled?(assigns :: map()) :: boolean()

  @doc """
  Checks if more sessions are available beyond the current count.

  ## Parameters
    * assigns - A map containing the necessary context
    * current_count - The number of sessions currently loaded

  ## Returns
    * `boolean()` - true if more sessions exist, false otherwise
  """
  @callback more_sessions?(
              assigns :: map(),
              current_count :: integer()
            ) :: boolean()

  @doc """
  Returns the placeholder text for the chat input field.

  ## Returns
    * `String.t()` - The placeholder text to display
  """
  @callback input_placeholder() :: String.t()

  @doc """
  Returns the title for a chat session.

  ## Parameters
    * session - The chat session

  ## Returns
    * `String.t()` - The title to display for the session
  """
  @callback chat_title(session :: map()) :: String.t()

  @doc """
  Indicates whether this mode supports template/code generation.

  ## Returns
    * `boolean()` - Whether this mode generates templates or code
  """
  @callback supports_template_generation?() :: boolean()

  @doc """
  Returns metadata about this mode for UI display and configuration.

  ## Returns
    * `map()` - Metadata including name, description, icon, etc.
  """
  @callback metadata() :: map()

  @doc """
  Handles what to do when the AI generates a response.
  The ui_callback function allows the mode to trigger UI updates.

  ## Parameters
    * assigns - The current assigns
    * session_or_message - The session or message that was generated
    * ui_callback - Function to call for UI updates

  ## Returns
    * `map()` - Updated assigns
  """
  @callback handle_response_generated(
              assigns :: map(),
              session_or_message :: map(),
              ui_callback :: function()
            ) :: map()

  @doc """
  Called when a new session starts, allows mode-specific initialization.

  ## Parameters
    * socket - The LiveView socket
    * ui_callback - Function to call for UI updates

  ## Returns
    * `map()` - Updated socket
  """
  @callback on_session_start(socket :: map(), ui_callback :: function()) :: map()

  # Optional callbacks with default implementations
  @optional_callbacks [
    input_placeholder: 0,
    chat_title: 1,
    supports_template_generation?: 0,
    metadata: 0,
    handle_response_generated: 3,
    on_session_start: 2
  ]

  defmacro __using__(_opts) do
    quote do
      @behaviour LightningWeb.Live.AiAssistant.ModeBehavior

      alias LightningWeb.Live.AiAssistant.ErrorHandler

      # Shared error handling
      def error_message(error), do: ErrorHandler.format_error(error)

      # Default implementations for optional callbacks
      def input_placeholder do
        "Open a previous session or send a message to start a new one"
      end

      def chat_title(session) do
        case session do
          %{title: title} when is_binary(title) and title != "" -> title
          _ -> "Untitled Chat"
        end
      end

      def supports_template_generation?, do: false

      def metadata do
        %{
          name: "AI Assistant",
          description: "General AI assistance",
          icon: "hero-cpu-chip"
        }
      end

      def handle_response_generated(assigns, _session_or_message, _ui_callback) do
        assigns
      end

      def on_session_start(socket, _ui_callback), do: socket

      defoverridable input_placeholder: 0,
                     chat_title: 1,
                     supports_template_generation?: 0,
                     metadata: 0,
                     handle_response_generated: 3,
                     on_session_start: 2,
                     error_message: 1
    end
  end
end
