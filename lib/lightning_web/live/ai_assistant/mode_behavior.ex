defmodule LightningWeb.Live.AiAssistant.ModeBehavior do
  @moduledoc """
  Contract for AI Assistant interaction modes.

  Each mode handles a specific type of AI assistance (job debugging, workflow generation, etc.)
  by implementing the required callbacks and optionally overriding defaults.
  """

  alias Lightning.AiAssistant.ChatMessage
  alias Lightning.AiAssistant.ChatSession
  alias LightningWeb.Live.AiAssistant.PaginationMeta

  @type assigns :: %{atom() => any()}
  @type session :: ChatSession.t()
  @type session_id :: Ecto.UUID.t()
  @type user :: Lightning.Accounts.User.t()
  @type job :: Lightning.Workflows.Job.t()
  @type project :: Lightning.Projects.Project.t()

  @type session_result :: {:ok, session()} | {:error, error_reason()}
  @type error_reason :: :validation_failed | :unauthorized | :not_found | term()
  @type sort_direction :: :asc | :desc

  @type list_opts :: [
          offset: non_neg_integer(),
          limit: pos_integer(),
          search: String.t() | nil
        ]

  @type session_list :: %{
          sessions: [session()],
          pagination: PaginationMeta.t()
        }

  @type mode_metadata :: %{
          optional(:category) => String.t(),
          optional(:features) => [String.t()],
          name: String.t(),
          description: String.t(),
          icon: String.t()
        }

  @type generated_code :: %{yaml: String.t()} | nil

  @doc """
  Creates a new AI session with initial message.

  Required assigns:
  - `:current_user` - User creating the session
  - Mode-specific context (`:selected_job`, `:project`, etc.)
  """
  @callback create_session(assigns(), String.t()) :: session_result()

  @doc """
  Loads session with mode-specific context enrichment.

  Required assigns:
  - `:chat_session_id` - Session UUID
  - Mode-specific context

  Raises when session not found.
  """
  @callback get_session!(assigns()) :: session() | no_return()

  @doc """
  Lists sessions filtered by mode context.

  Required assigns vary by mode (e.g., `:selected_job`, `:project`).
  """
  @callback list_sessions(assigns(), sort_direction(), list_opts()) ::
              session_list()

  @doc """
  Adds user message to session.

  Required assigns:
  - `:session` - Target session
  - `:current_user` - Message author
  """
  @callback save_message(assigns(), String.t()) :: session_result()

  @doc """
  Sends message to AI service with mode context.
  """
  @callback query(session(), String.t(), Keyword.t()) :: session_result()

  @doc """
  Checks if chat input should be disabled.
  """
  @callback chat_input_disabled?(assigns()) :: boolean()

  @doc """
  Checks if more sessions exist beyond current count.
  """
  @callback more_sessions?(assigns(), current_count :: integer()) :: boolean()

  # Optional callbacks - have default implementations

  @doc """
  Validates form input parameters.
  """
  @callback validate_form_changeset(params :: map()) :: Ecto.Changeset.t()

  @doc """
  Extracts options from assigns for query processing.
  """
  @callback query_options(assigns()) :: Keyword.t()

  @doc """
  Whether to show attachment options UI.
  """
  @callback enable_attachment_options_component?() :: boolean()

  @doc """
  Placeholder text for chat input.
  """
  @callback input_placeholder() :: String.t()

  @doc """
  Formats session title for display.
  """
  @callback chat_title(session()) :: String.t()

  @doc """
  Whether mode generates applicable templates/code.
  """
  @callback supports_template_generation?() :: boolean()

  @doc """
  UI metadata for mode selection.
  """
  @callback metadata() :: mode_metadata()

  @doc """
  Extracts generated code from AI response.
  """
  @callback extract_generated_code(session() | ChatMessage.t()) ::
              generated_code()

  @doc """
  Handles new session initialization.
  """
  @callback on_session_start(Phoenix.LiveView.Socket.t(), (atom(), any() ->
                                                             any())) ::
              Phoenix.LiveView.Socket.t()

  @optional_callbacks [
    validate_form_changeset: 1,
    query_options: 1,
    enable_attachment_options_component?: 0,
    input_placeholder: 0,
    chat_title: 1,
    supports_template_generation?: 0,
    metadata: 0,
    extract_generated_code: 1,
    on_session_start: 2
  ]

  defmacro __using__(_opts) do
    quote do
      @behaviour LightningWeb.Live.AiAssistant.ModeBehavior

      alias LightningWeb.Live.AiAssistant.ErrorHandler

      def input_placeholder do
        "Open a previous session or send a message to start a new one"
      end

      def validate_form_changeset(params) do
        data = %{content: nil}
        types = %{content: :string}

        {data, types}
        |> Ecto.Changeset.cast(params, Map.keys(types))
      end

      def query_options(_assigns), do: []

      def enable_attachment_options_component?, do: false

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

      def extract_generated_code(_session_or_message), do: nil

      def on_session_start(socket, _ui_callback), do: socket

      def error_message(error), do: ErrorHandler.format_error(error)

      defoverridable input_placeholder: 0,
                     chat_title: 1,
                     supports_template_generation?: 0,
                     metadata: 0,
                     extract_generated_code: 1,
                     on_session_start: 2,
                     error_message: 1,
                     validate_form_changeset: 1,
                     query_options: 1,
                     enable_attachment_options_component?: 0
    end
  end
end
