defmodule LightningWeb.Live.AiAssistant.ModeBehavior do
  @moduledoc """
  Defines the contract for AI Assistant interaction modes.

  Each mode implements different AI assistance functionality (e.g., job code help, workflow generation).
  The component delegates all mode-specific decisions to the implementing module.
  """

  alias Lightning.AiAssistant.ChatMessage
  alias Lightning.AiAssistant.ChatSession
  alias LightningWeb.Live.AiAssistant.PaginationMeta
  alias Phoenix.LiveView.Socket

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
          icon: String.t(),
          chat_param: String.t()
        }

  @type update_result :: {:ok, Socket.t()} | {:unhandled, Socket.t()}

  @doc """
  Creates a new chat session with initial content.
  """
  @callback create_session(assigns(), String.t(), opts :: Keyword.t()) ::
              session_result()

  @doc """
  Retrieves an existing session by ID from assigns.
  """
  @callback get_session!(assigns()) :: session() | no_return()

  @doc """
  Lists chat sessions with pagination support.
  """
  @callback list_sessions(assigns(), sort_direction(), list_opts()) ::
              session_list()

  @doc """
  Saves a user message to the current session.
  """
  @callback save_message(assigns(), String.t()) :: session_result()

  @doc """
  Sends a query to the AI service.
  """
  @callback query(session(), String.t(), Keyword.t()) :: session_result()

  @doc """
  Determines if the chat input should be disabled.
  """
  @callback chat_input_disabled?(assigns()) :: boolean()

  @doc """
  Checks if more sessions are available beyond the current count.
  """
  @callback more_sessions?(assigns(), current_count :: integer()) :: boolean()

  @doc """
  Returns mode metadata for UI display.
  """
  @callback metadata() :: mode_metadata()

  @doc """
  Called when a message is sent.
  """
  @callback on_message_send(Socket.t()) :: Socket.t()

  @doc """
  Called when an AI response is received.
  """
  @callback on_message_received(Socket.t(), session()) :: Socket.t()

  @doc """
  Called when a chat session is closed.
  """
  @callback on_session_close(Socket.t()) :: Socket.t()

  @doc """
  Called when a chat session is opened.
  """
  @callback on_session_open(Socket.t(), session()) :: Socket.t()

  @doc """
  Called when a message is selected in the UI.
  """
  @callback on_message_selected(Socket.t(), ChatMessage.t()) :: Socket.t()

  @doc """
  Renders mode-specific configuration form elements.
  """
  @callback render_config_form(assigns()) ::
              Phoenix.LiveView.Rendered.t() | nil

  @doc """
  Returns the form module for this mode.
  """
  @callback form_module() :: module()

  @doc """
  Validates form parameters.
  """
  @callback validate_form(params :: map()) :: Ecto.Changeset.t()

  @doc """
  Extracts options from a validated changeset.
  """
  @callback extract_form_options(Ecto.Changeset.t()) :: Keyword.t()

  @doc """
  Returns placeholder text for the chat input.
  """
  @callback input_placeholder() :: String.t()

  @doc """
  Returns a display title for the chat session.
  """
  @callback chat_title(session()) :: String.t()

  @doc """
  Formats an error for display.
  """
  @callback error_message(any()) :: String.t()

  @doc """
  Returns tooltip text when chat is disabled.
  """
  @callback disabled_tooltip_message(assigns()) :: String.t() | nil

  @optional_callbacks [
    input_placeholder: 0,
    chat_title: 1,
    error_message: 1,
    disabled_tooltip_message: 1,
    render_config_form: 1,
    on_message_received: 2,
    on_session_close: 1,
    on_session_open: 2
  ]

  defmacro __using__(_opts) do
    quote do
      @behaviour LightningWeb.Live.AiAssistant.ModeBehavior

      alias LightningWeb.Live.AiAssistant.ErrorHandler
      alias Phoenix.LiveView.Socket

      @doc false
      def input_placeholder do
        "Open a previous session or send a message to start a new one"
      end

      @doc false
      def chat_title(session) do
        case session do
          %{title: title} when is_binary(title) and title != "" -> title
          _ -> "Untitled Chat"
        end
      end

      @doc false
      def error_message(error), do: ErrorHandler.format_error(error)

      @doc false
      def disabled_tooltip_message(_assigns), do: nil

      @doc false
      def render_config_form(_assigns), do: nil

      # Default event handlers - just pass through

      @doc false
      def on_message_send(socket), do: socket

      @doc false
      def on_message_received(socket, _session), do: socket

      @doc false
      def on_session_close(socket), do: socket

      @doc false
      def on_session_open(socket, _session), do: socket

      @doc false
      def on_message_selected(socket, _message), do: socket

      @doc false
      def form_module, do: __MODULE__.DefaultForm

      @doc false
      def validate_form(params) do
        form_module().changeset(params)
      end

      @doc false
      def extract_form_options(changeset) do
        form_module().extract_options(changeset)
      end

      defmodule DefaultForm do
        @moduledoc false

        use Ecto.Schema
        import Ecto.Changeset

        @primary_key false
        embedded_schema do
          field :content, :string
        end

        @doc false
        def changeset(params \\ %{}) do
          %__MODULE__{}
          |> cast(params, [:content])
          |> validate_required([:content],
            message: "Please enter a message before sending"
          )
          |> validate_length(:content,
            min: 1,
            message: "Please enter a message before sending"
          )
        end

        @doc false
        def extract_options(_changeset), do: []
      end

      defoverridable input_placeholder: 0,
                     chat_title: 1,
                     error_message: 1,
                     disabled_tooltip_message: 1,
                     render_config_form: 1,
                     on_message_send: 1,
                     on_message_received: 2,
                     on_session_close: 1,
                     on_session_open: 2,
                     on_message_selected: 2,
                     form_module: 0,
                     validate_form: 1,
                     extract_form_options: 1
    end
  end
end
