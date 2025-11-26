defmodule LightningWeb.API.AiAssistantController do
  @moduledoc """
  API endpoints for AI Assistant functionality.
  """
  use LightningWeb, :controller

  alias Lightning.AiAssistant
  alias Lightning.Jobs
  alias Lightning.Projects
  alias Lightning.Workflows
  alias Lightning.Policies.Permissions

  action_fallback LightningWeb.FallbackController

  @doc """
  List AI Assistant sessions for a given context (job or project).

  ## Parameters
  - `session_type`: "job_code" or "workflow_template" (required)
  - `job_id`: Job ID (required if session_type is "job_code")
  - `project_id`: Project ID (required if session_type is "workflow_template")
  - `offset`: Pagination offset (optional, default: 0)
  - `limit`: Pagination limit (optional, default: 20)

  ## Examples
  - GET /api/ai_assistant/sessions?session_type=job_code&job_id=123
  - GET /api/ai_assistant/sessions?session_type=workflow_template&project_id=456
  """
  def list_sessions(conn, params) do
    require Logger
    user = conn.assigns[:current_user]

    Logger.debug("[AI Assistant API] list_sessions called", %{
      params: params,
      user_id: user.id
    })

    with {:ok, session_type} <- validate_session_type(params),
         {:ok, resource} <- get_resource(session_type, params),
         :ok <- authorize_access(session_type, resource, user) do
      offset = Map.get(params, "offset", "0") |> String.to_integer()
      limit = Map.get(params, "limit", "20") |> String.to_integer()

      resource_id = if is_binary(resource), do: resource, else: resource.id

      Logger.debug("[AI Assistant API] Fetching sessions", %{
        session_type: session_type,
        resource_id: resource_id,
        offset: offset,
        limit: limit
      })

      %{sessions: sessions, pagination: pagination} =
        AiAssistant.list_sessions(resource, :desc,
          offset: offset,
          limit: limit
        )

      Logger.debug("[AI Assistant API] Sessions fetched", %{
        count: length(sessions),
        total_count: pagination.total_count
      })

      formatted_sessions = Enum.map(sessions, &format_session/1)

      json(conn, %{
        sessions: formatted_sessions,
        pagination: %{
          total_count: pagination.total_count,
          has_next_page: pagination.has_next_page,
          has_prev_page: pagination.has_prev_page
        }
      })
    end
  end

  # Private helpers

  defp validate_session_type(%{"session_type" => session_type})
       when session_type in ["job_code", "workflow_template"] do
    {:ok, session_type}
  end

  defp validate_session_type(_params) do
    {:error, :bad_request}
  end

  defp get_resource("job_code", %{"job_id" => job_id}) do
    # Don't require job to exist in DB - just pass the ID
    # The list_sessions logic will handle both saved and unsaved jobs
    {:ok, job_id}
  end

  defp get_resource("job_code", _params) do
    {:error, :bad_request}
  end

  defp get_resource("workflow_template", %{"project_id" => project_id}) do
    case Projects.get_project(project_id) do
      nil -> {:error, :not_found}
      project -> {:ok, project}
    end
  end

  defp get_resource("workflow_template", _params) do
    {:error, :bad_request}
  end

  defp authorize_access("job_code", job_id, user) when is_binary(job_id) do
    alias Lightning.AiAssistant.ChatSession
    alias Lightning.Repo
    import Ecto.Query

    # Try to load job from database - if it exists, check via workflow
    case Jobs.get_job(job_id) do
      {:ok, job} ->
        workflow = Workflows.get_workflow(job.workflow_id)
        project = Projects.get_project(workflow.project_id)
        project_user = Projects.get_project_user(project, user)

        case Permissions.can(:workflows, :access_read, user, project_user) do
          :ok -> :ok
          {:error, _reason} -> {:error, :forbidden}
        end

      {:error, :not_found} ->
        # Job doesn't exist yet (unsaved)
        # Try to find any session with this job_id to get workflow_id
        session =
          from(s in ChatSession,
            where: s.session_type == "job_code",
            where:
              s.job_id == ^job_id or
                fragment("? -> 'unsaved_job' ->> 'id' = ?", s.meta, ^job_id),
            limit: 1
          )
          |> Repo.one()

        case session do
          nil ->
            # No sessions for this job - allow it (user might be creating first session)
            :ok

          %{meta: %{"unsaved_job" => %{"workflow_id" => workflow_id}}} ->
            # Unsaved job - check via workflow from meta
            workflow = Workflows.get_workflow(workflow_id)
            project = Projects.get_project(workflow.project_id)
            project_user = Projects.get_project_user(project, user)

            case Permissions.can(:workflows, :access_read, user, project_user) do
              :ok -> :ok
              {:error, _reason} -> {:error, :forbidden}
            end

          %{job_id: saved_job_id} when not is_nil(saved_job_id) ->
            # Session was for a saved job that might have been deleted
            # Try to get workflow through the job
            case Jobs.get_job(saved_job_id) do
              {:ok, job} ->
                workflow = Workflows.get_workflow(job.workflow_id)
                project = Projects.get_project(workflow.project_id)
                project_user = Projects.get_project_user(project, user)

                case Permissions.can(
                       :workflows,
                       :access_read,
                       user,
                       project_user
                     ) do
                  :ok -> :ok
                  {:error, _reason} -> {:error, :forbidden}
                end

              {:error, :not_found} ->
                # Job was deleted - allow access to sessions
                :ok
            end

          _ ->
            :ok
        end
    end
  end

  defp authorize_access("workflow_template", project, user) do
    project_user = Projects.get_project_user(project, user)

    case Permissions.can(:workflows, :access_read, user, project_user) do
      :ok -> :ok
      {:error, _reason} -> {:error, :forbidden}
    end
  end

  defp format_session(session) do
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

      _ ->
        base
    end
  end

  defp format_job_code_session(base, session) do
    # Check for unsaved job data first
    unsaved_job = session.meta["unsaved_job"]

    cond do
      # Unsaved job - get data from meta
      unsaved_job ->
        workflow = Workflows.get_workflow(unsaved_job["workflow_id"])

        Map.merge(base, %{
          job_name: unsaved_job["name"],
          workflow_name: workflow.name,
          is_unsaved: true
        })

      # Saved job - get from database
      session.job_id ->
        case Jobs.get_job(session.job_id) do
          {:ok, job} ->
            workflow = Workflows.get_workflow(job.workflow_id)

            Map.merge(base, %{
              job_name: job.name,
              workflow_name: workflow.name
            })

          {:error, :not_found} ->
            # Job was deleted
            Map.merge(base, %{
              job_name: "(deleted job)",
              workflow_name: nil
            })
        end

      # No job data
      true ->
        base
    end
  end

  defp format_workflow_template_session(base, session) do
    project = session.project || Projects.get_project(session.project_id)

    workflow_name =
      if session.workflow_id do
        workflow = Workflows.get_workflow(session.workflow_id)
        workflow.name
      else
        nil
      end

    Map.merge(base, %{
      project_name: project.name,
      workflow_name: workflow_name
    })
  end
end
