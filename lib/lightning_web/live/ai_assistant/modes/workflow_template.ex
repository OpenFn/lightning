defmodule LightningWeb.Live.AiAssistant.Modes.WorkflowTemplate do
  @moduledoc """
  AI mode for generating Lightning workflow templates.

  Handles workflow creation through natural language descriptions and
  supports external callbacks for workflow code integration.
  """

  use LightningWeb.Live.AiAssistant.ModeBehavior

  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.ChatMessage
  alias Lightning.AiAssistant.ChatSession
  alias LightningWeb.Live.AiAssistant.ErrorHandler

  require Logger

  @type project :: Lightning.Projects.Project.t()
  @type user :: Lightning.Accounts.User.t()
  @type session :: ChatSession.t()
  @type workflow_yaml :: String.t()
  @type assigns :: %{atom() => any()}

  @impl true
  @spec create_session(assigns(), String.t(), Keyword.t()) ::
          {:ok, session()} | {:error, term()}
  def create_session(
        %{project: project, user: user} = assigns,
        content,
        _opts \\ []
      ) do
    AiAssistant.create_workflow_session(
      project,
      nil,
      assigns[:workflow],
      user,
      content,
      code: assigns[:code]
    )
  end

  @impl true
  @spec get_session!(assigns()) :: session()
  def get_session!(%{chat_session_id: session_id}) do
    AiAssistant.get_session!(session_id)
  end

  @impl true
  @spec list_sessions(assigns(), :asc | :desc, Keyword.t()) :: %{
          sessions: [session()],
          pagination: map()
        }
  def list_sessions(%{project: project} = assigns, sort_direction, opts \\ []) do
    workflow = assigns[:workflow]
    opts_with_workflow = Keyword.put_new(opts, :workflow, workflow)
    AiAssistant.list_sessions(project, sort_direction, opts_with_workflow)
  end

  @impl true
  @spec more_sessions?(assigns(), integer()) :: boolean()
  def more_sessions?(%{project: project}, current_count) do
    AiAssistant.has_more_sessions?(project, current_count)
  end

  @impl true
  @spec save_message(assigns(), String.t()) ::
          {:ok, session()} | {:error, term()}
  def save_message(
        %{session: session, user: user, code: code},
        content
      ) do
    AiAssistant.save_message(
      session,
      %{role: :user, content: content, user: user},
      code: code
    )
  end

  @impl true
  @spec query(session(), String.t(), Keyword.t()) ::
          {:ok, session()} | {:error, term()}
  def query(session, content, opts \\ []) do
    AiAssistant.query_workflow(session, content, opts)
  end

  @impl true
  @spec chat_input_disabled?(assigns()) :: boolean()
  def chat_input_disabled?(%{
        can_edit: can_edit,
        ai_limit_result: limit_result,
        endpoint_available: available,
        pending_message: pending
      }) do
    !can_edit or
      limit_result != :ok or
      !available or
      !is_nil(pending.loading)
  end

  @impl true
  @spec input_placeholder() :: String.t()
  def input_placeholder do
    "Describe the workflow you want to create..."
  end

  @impl true
  @spec chat_title(session()) :: String.t()
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

  @impl true
  @spec metadata() :: map()
  def metadata do
    %{
      name: "Workflow Builder",
      description: "Generate complete workflows from your descriptions",
      icon: "hero-cpu-chip",
      chat_param: "w-chat"
    }
  end

  @impl true
  @spec disabled_tooltip_message(assigns()) :: String.t() | nil
  def disabled_tooltip_message(assigns) do
    case {assigns.can_edit, assigns.ai_limit_result} do
      {false, _} ->
        "You are not authorized to use the AI Assistant"

      {_, error} when error != :ok ->
        ErrorHandler.format_limit_error(error)

      _ ->
        nil
    end
  end

  @impl true
  @spec on_message_send(Phoenix.LiveView.Socket.t()) ::
          Phoenix.LiveView.Socket.t()
  def on_message_send(socket) do
    invoke_callback(socket, :on_message_send)
  end

  @impl true
  @spec on_message_received(Phoenix.LiveView.Socket.t(), session()) ::
          Phoenix.LiveView.Socket.t()
  def on_message_received(socket, session) do
    handle_code_event(socket, session, :on_message_received)
  end

  @impl true
  @spec on_session_close(Phoenix.LiveView.Socket.t()) ::
          Phoenix.LiveView.Socket.t()
  def on_session_close(socket) do
    invoke_callback(socket, :on_session_close)
  end

  @impl true
  @spec on_session_open(Phoenix.LiveView.Socket.t(), session()) ::
          Phoenix.LiveView.Socket.t()
  def on_session_open(socket, session) do
    if socket.assigns.selected_message do
      socket
    else
      handle_code_event(socket, session, :on_session_open)
    end
  end

  @impl true
  @spec on_message_selected(Phoenix.LiveView.Socket.t(), ChatMessage.t()) ::
          Phoenix.LiveView.Socket.t()
  def on_message_selected(socket, message) do
    handle_code_event(socket, message, :on_message_selected)
  end

  @impl true
  @spec form_module() :: module()
  def form_module, do: __MODULE__.DefaultForm

  @impl true
  @spec validate_form(map()) :: Ecto.Changeset.t()
  def validate_form(params) do
    form_module().changeset(params)
  end

  @impl true
  @spec extract_form_options(Ecto.Changeset.t()) :: Keyword.t()
  def extract_form_options(_changeset) do
    []
  end

  @doc false
  @spec invoke_callback(Phoenix.LiveView.Socket.t(), atom(), list()) ::
          Phoenix.LiveView.Socket.t()
  defp invoke_callback(socket, callback_name, args \\ []) do
    callback = get_in(socket.assigns, [:callbacks, callback_name])

    if callback do
      apply(callback, args)
    end

    socket
  end

  @doc false
  @spec handle_code_event(
          Phoenix.LiveView.Socket.t(),
          session() | ChatMessage.t(),
          atom()
        ) ::
          Phoenix.LiveView.Socket.t()
  defp handle_code_event(socket, data, callback_name) do
    case extract_code(data) do
      nil ->
        socket

      code ->
        invoke_callback(socket, callback_name, [code, data])
    end
  end

  @doc false
  @spec extract_code(session() | ChatMessage.t()) :: String.t() | nil
  defp extract_code(%ChatSession{messages: messages}) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(&extract_message_code/1)
  end

  defp extract_code(%ChatMessage{code: code}) do
    if valid_code?(code), do: code
  end

  @doc false
  @spec extract_message_code(map()) :: String.t() | nil
  defp extract_message_code(%{code: code}) do
    if valid_code?(code), do: code
  end

  @doc false
  @spec valid_code?(any()) :: boolean()
  defp valid_code?(code) when is_binary(code) and code != "", do: true
  defp valid_code?(_), do: false
end
