defmodule LightningWeb.Channels.AiAssistantJSON do
  @moduledoc """
  Renders AI Assistant data structures for channels and controllers.

  Provides consistent JSON formatting for chat sessions across the API
  controller and Phoenix channel.
  """

  alias Lightning.Projects

  @doc """
  Formats a chat session for API/channel responses.

  Returns a map with session metadata including type-specific fields
  (job_name/workflow_name for job_code, project_name/workflow_name for workflow_template).

  ## Examples

      iex> format_session(session)
      %{
        id: "uuid",
        title: "Session title",
        session_type: "job_code",
        message_count: 5,
        updated_at: ~U[2024-01-01 00:00:00Z],
        job_name: "My Job",
        workflow_name: "My Workflow"
      }
  """
  def format_session(session) do
    base = %{
      id: session.id,
      title: session.title,
      session_type: session.session_type,
      message_count: session.message_count || 0,
      updated_at: session.updated_at
    }

    case session.session_type do
      "job_code" ->
        format_job_code_session(base, session)

      "workflow_template" ->
        format_workflow_template_session(base, session)
    end
  end

  @doc """
  Formats a list of chat sessions.
  """
  def format_sessions(sessions) do
    Enum.map(sessions, &format_session/1)
  end

  defp format_job_code_session(base, session) do
    cond do
      session.meta["unsaved_job"] ->
        unsaved_job = session.meta["unsaved_job"]
        # Use preloaded workflow association
        Map.merge(base, %{
          job_name: unsaved_job["name"],
          workflow_name: session.workflow && session.workflow.name,
          is_unsaved: true
        })

      session.job && session.job.workflow ->
        # Use preloaded job and workflow associations
        Map.merge(base, %{
          job_name: session.job.name,
          workflow_name: session.job.workflow.name
        })

      session.job ->
        # Job exists but workflow may have been deleted
        Map.merge(base, %{
          job_name: session.job.name,
          workflow_name: nil
        })

      true ->
        # Job was deleted
        Map.merge(base, %{
          job_name: "[Deleted Job]",
          workflow_name: nil
        })
    end
  end

  defp format_workflow_template_session(base, session) do
    # Use preloaded project association
    project_name =
      cond do
        session.project -> session.project.name
        session.project_id -> Projects.get_project(session.project_id).name
        true -> nil
      end

    # Use preloaded workflow association
    workflow_name = session.workflow && session.workflow.name

    Map.merge(base, %{
      project_name: project_name,
      workflow_name: workflow_name
    })
  end
end
