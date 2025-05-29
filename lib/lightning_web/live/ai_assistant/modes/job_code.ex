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

  @impl true
  def create_session(%{selected_job: job, current_user: user}, content) do
    case AiAssistant.create_session(job, user, content) do
      {:ok, session} -> {:ok, session}
      error -> error
    end
  end

  @impl true
  def get_session!(session_id, %{selected_job: job}) do
    AiAssistant.get_session!(session_id)
    |> AiAssistant.put_expression_and_adaptor(job.body, job.adaptor)
  end

  @impl true
  def list_sessions(%{selected_job: selected_job}, sort_direction) do
    AiAssistant.list_sessions_for_job(selected_job, sort_direction)
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
      !is_nil(pending_message.loading) or job_is_unsaved?(selected_job)
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
      icon: "hero-code-bracket"
    }
  end

  def disabled_tooltip_message(%{
        can_edit_workflow: can_edit_workflow,
        ai_limit_result: ai_limit_result,
        selected_job: selected_job
      }) do
    case {can_edit_workflow, ai_limit_result, selected_job} do
      {false, _, _} ->
        "You are not authorized to use the Ai Assistant"

      {_, {:error, _reason, _msg} = error, _} ->
        error_message(error)

      {_, _, %{__meta__: %{state: :built}}} ->
        "Save the job first in order to use the AI Assistant"

      _ ->
        nil
    end
  end

  def error_message({:error, message}) when is_binary(message) do
    message
  end

  def error_message({:error, %Ecto.Changeset{}}) do
    "Could not save message. Please try again."
  end

  def error_message({:error, _reason, %{text: text_message}}) do
    text_message
  end

  def error_message(_error) do
    "Oops! Something went wrong. Please try again."
  end

  defp has_reached_limit?(ai_limit_result) do
    ai_limit_result != :ok
  end

  defp job_is_unsaved?(%{__meta__: %{state: :built}} = _job) do
    true
  end

  defp job_is_unsaved?(_job), do: false
end
