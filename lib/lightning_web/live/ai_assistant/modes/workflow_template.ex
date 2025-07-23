defmodule LightningWeb.Live.AiAssistant.Modes.WorkflowTemplate do
  @moduledoc """
  AI mode for generating Lightning workflow templates from natural language.

  Transforms user descriptions into complete YAML workflow templates,
  enabling non-technical users to create complex data integration workflows.
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

  @doc """
  Creates project-scoped workflow generation session.
  """
  @impl true
  def create_session(
        %{project: project, current_user: user} = assigns,
        content
      ) do
    workflow = assigns[:workflow]

    AiAssistant.create_workflow_session(project, workflow, user, content,
      workflow_code: assigns[:workflow_code]
    )
  end

  @doc """
  Loads session without additional context.
  """
  @impl true
  def get_session!(%{chat_session_id: session_id}) do
    AiAssistant.get_session!(session_id)
  end

  @doc """
  Lists all workflow sessions for the project.
  """
  @impl true
  def list_sessions(%{project: project} = assigns, sort_direction, opts \\ []) do
    workflow = assigns[:workflow]
    opts_with_workflow = Keyword.put_new(opts, :workflow, workflow)
    AiAssistant.list_sessions(project, sort_direction, opts_with_workflow)
  end

  @doc """
  Checks for more project workflow sessions.
  """
  @impl true
  def more_sessions?(%{project: project}, current_count) do
    AiAssistant.has_more_sessions?(project, current_count)
  end

  @doc """
  Saves message with optional workflow code context.
  """
  @impl true
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
  Queries workflow-specific AI endpoint.
  """
  @impl true
  def query(session, content, opts \\ []) do
    AiAssistant.query_workflow(session, content, opts)
  end

  @doc """
  Passes workflow code as query context.
  """
  @impl true
  def query_options(%{workflow_code: workflow_code}) do
    [workflow_code: workflow_code]
  end

  @doc """
  Disabled when: no edit permission, AI limit reached, endpoint down, or loading.
  """
  @impl true
  @spec chat_input_disabled?(map()) :: boolean()
  def chat_input_disabled?(%{
        can_edit_workflow: can_edit,
        ai_limit_result: limit_result,
        endpoint_available?: available?,
        pending_message: pending
      }) do
    !can_edit or
      limit_result != :ok or
      !available? or
      !is_nil(pending.loading)
  end

  @doc """
  Prompts for workflow description.
  """
  @impl true
  def input_placeholder do
    "Describe the workflow you want to create..."
  end

  @doc """
  Uses project name in title when available.
  """
  @impl true
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
  def supports_template_generation?, do: true

  @doc """
  Workflow builder metadata.
  """
  @impl true
  def metadata do
    %{
      name: "Workflow Builder",
      description: "Generate complete workflows from your descriptions",
      icon: "hero-cpu-chip"
    }
  end

  defp extract_generated_code(session_or_message) do
    case extract_workflow_yaml(session_or_message) do
      nil -> nil
      yaml -> %{yaml: yaml}
    end
  end

  @doc """
  Clears existing template on new session.
  """
  @impl true
  def on_session_start(socket, ui_callback) do
    ui_callback.(:clear_template, nil)
    socket
  end

  @doc """
  Returns tooltip message when input is disabled.
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

  defp extract_workflow_yaml(%ChatSession{messages: messages}) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn message ->
      if has_workflow_code?(message.workflow_code), do: message.workflow_code
    end)
  end

  defp extract_workflow_yaml(%ChatMessage{workflow_code: code}) do
    if has_workflow_code?(code), do: code
  end

  defp has_workflow_code?(code) when is_binary(code), do: code != ""
  defp has_workflow_code?(_), do: false

  def apply_changes(socket, session_or_message) do
    case extract_generated_code(session_or_message) do
      nil ->
        socket

      %{yaml: yaml} ->
        Phoenix.LiveView.send_update(
          socket.assigns.parent_module,
          id: socket.assigns.parent_id,
          action: :workflow_updated,
          workflow_code: yaml,
          session_or_message: session_or_message
        )

        socket
    end
  end
end
