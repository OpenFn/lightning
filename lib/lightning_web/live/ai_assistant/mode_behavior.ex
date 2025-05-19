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
end
