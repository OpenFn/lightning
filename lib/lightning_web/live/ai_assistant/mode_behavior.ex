defmodule LightningWeb.Live.AiAssistant.ModeBehavior do
  @moduledoc """
  Defines the behavior for AI Assistant modes.
  Each mode must implement these callbacks to handle mode-specific operations.
  """

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
  Lists all sessions for the given mode and context.

  ## Parameters
    * assigns - A map containing the necessary context for session listing
    * sort_direction - The direction to sort sessions (:asc or :desc)

  ## Returns
    * `[session]` - A list of sessions for this mode
  """
  @callback list_sessions(
              assigns :: map(),
              sort_direction :: atom()
            ) :: [map()]

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
  """
  @callback handle_response_generated(
              assigns :: map(),
              session_or_message :: map(),
              ui_callback :: function()
            ) :: map()

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

      # Default implementations for optional callbacks
      def input_placeholder do
        "Open a previous session or send a message to start a new one"
      end

      def chat_title(session) do
        session.title || "Untitled Chat"
      end

      def supports_template_generation?, do: false

      def metadata do
        %{
          name: "AI Assistant",
          description: "General AI assistance",
          icon: "hero-cpu-chip"
        }
      end

      def handle_response_generated(assigns, _session_or_message, _ui_callback),
        do: assigns

      def on_session_start(socket, _ui_callback), do: socket

      defoverridable input_placeholder: 0,
                     chat_title: 1,
                     supports_template_generation?: 0,
                     metadata: 0,
                     handle_response_generated: 3,
                     on_session_start: 2
    end
  end
end
