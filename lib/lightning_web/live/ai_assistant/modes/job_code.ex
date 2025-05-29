defmodule LightningWeb.Live.AiAssistant.Modes.JobCode do
  @moduledoc """
  Implementation of the ModeBehavior protocol for job code assistance.

  This module provides functionality for AI-assisted job code development and debugging.
  It implements the `ModeBehavior` protocol to handle job-specific operations like
  session creation, message handling, and code assistance.

  ## Features
  * Creates job-specific chat sessions
  * Handles user messages and AI responses
  * Provides code assistance and debugging help
  * Manages job-specific context including adaptor and expression
  """

  use LightningWeb.Live.AiAssistant.ModeBehavior

  alias Lightning.AiAssistant
  alias LightningWeb.Live.AiAssistant.ErrorHandler

  @impl true
  def create_session(%{selected_job: job, current_user: user}, content) do
    AiAssistant.create_session(job, user, content)
  end

  @impl true
  def get_session!(session_id, %{selected_job: job}) do
    AiAssistant.get_session!(session_id)
    |> AiAssistant.put_expression_and_adaptor(job.body, job.adaptor)
  end

  @impl true
  def list_sessions(%{selected_job: job}, sort_direction, opts \\ []) do
    AiAssistant.list_sessions(job, sort_direction, opts)
  end

  @impl true
  def more_sessions?(%{selected_job: job}, current_count) do
    AiAssistant.has_more_sessions?(job, current_count)
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
    AiAssistant.query(session, content)
  end

  @impl true
  def chat_input_disabled?(%{
        selected_job: selected_job,
        can_edit_workflow: can_edit_workflow,
        ai_limit_result: ai_limit_result,
        endpoint_available?: endpoint_available?,
        pending_message: pending_message
      }) do
    !can_edit_workflow or
      has_reached_limit?(ai_limit_result) or
      !endpoint_available? or
      !is_nil(pending_message.loading) or
      job_is_unsaved?(selected_job)
  end

  @impl true
  def input_placeholder do
    "Ask about your job code, debugging, or OpenFn adaptors..."
  end

  @impl true
  def chat_title(session) do
    case session do
      %{title: title} when is_binary(title) and title != "" ->
        title

      %{job: %{name: job_name}} when is_binary(job_name) and job_name != "" ->
        "Help with #{job_name}"

      _ ->
        "Job Code Help"
    end
  end

  @impl true
  def supports_template_generation?, do: false

  @impl true
  def metadata do
    %{
      name: "Job Code Assistant",
      description: "Get help with job code, debugging, and OpenFn adaptors",
      icon: "hero-cpu-chip"
    }
  end

  def disabled_tooltip_message(assigns) do
    case {assigns.can_edit_workflow, assigns.ai_limit_result,
          assigns.selected_job} do
      {false, _, _} ->
        "You are not authorized to use the AI Assistant"

      {_, error, _} when error != :ok ->
        ErrorHandler.format_limit_error(error)

      {_, _, %{__meta__: %{state: :built}}} ->
        "Save the job first to use the AI Assistant"

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

  defp job_is_unsaved?(%{__meta__: %{state: :built}}), do: true
  defp job_is_unsaved?(_job), do: false
end
