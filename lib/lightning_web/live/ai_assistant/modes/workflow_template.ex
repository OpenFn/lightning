defmodule LightningWeb.Live.AiAssistant.Modes.WorkflowTemplate do
  @moduledoc """
  Implementation of the ModeBehavior protocol for workflow template generation.

  This module provides functionality for generating and managing workflow templates
  through the AI Assistant. It implements the `ModeBehavior` protocol to handle
  workflow-specific operations like session creation, message handling, and
  template generation.

  ## Features
  * Creates workflow-specific chat sessions
  * Handles user messages and AI responses
  * Generates workflow templates in YAML format
  * Manages workflow-specific context and state
  """

  use LightningWeb.Live.AiAssistant.ModeBehavior

  alias Lightning.AiAssistant
  alias LightningWeb.Live.AiAssistant.ErrorHandler

  @impl true
  def create_session(%{project: project, current_user: current_user}, content) do
    AiAssistant.create_workflow_session(project, current_user, content)
  end

  @impl true
  def get_session!(session_id, _assigns) do
    AiAssistant.get_session!(session_id)
  end

  @impl true
  def list_sessions(%{project: project}, sort_direction, opts \\ []) do
    AiAssistant.list_sessions(project, sort_direction, opts)
  end

  @impl true
  def more_sessions?(%{project: project}, current_count) do
    AiAssistant.has_more_sessions?(project, current_count)
  end

  @impl true
  def save_message(%{session: session, current_user: user}, content) do
    AiAssistant.save_message(session, %{
      role: :user,
      content: content,
      user: user
    })
  end

  @impl true
  def query(session, content) do
    AiAssistant.query_workflow(session, content)
  end

  @impl true
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

  @impl true
  def input_placeholder do
    "Describe the workflow you want to create..."
  end

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

  @impl true
  def metadata do
    %{
      name: "Workflow Builder",
      description: "Generate complete workflows from your descriptions",
      icon: "hero-cpu-chip"
    }
  end

  @impl true
  def handle_response_generated(assigns, session_or_message, ui_callback) do
    case extract_workflow_code(session_or_message) do
      nil ->
        assigns

      code ->
        ui_callback.(:workflow_code_generated, code)
        assigns
    end
  end

  @impl true
  def on_session_start(socket, ui_callback) do
    ui_callback.(:clear_template, nil)
    socket
  end

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
