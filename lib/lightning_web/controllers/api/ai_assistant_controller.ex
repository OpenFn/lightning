defmodule LightningWeb.API.AiAssistantController do
  @moduledoc """
  API endpoints for AI Assistant functionality.
  """
  use LightningWeb, :controller

  alias Lightning.AiAssistant
  alias Lightning.Jobs
  alias Lightning.Policies.Permissions
  alias Lightning.Projects
  alias Lightning.Workflows

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
    user = conn.assigns[:current_user]

    with {:ok, session_type} <- validate_session_type(params),
         {:ok, resource} <- get_resource(session_type, params),
         :ok <- authorize_access(session_type, resource, user) do
      offset = Map.get(params, "offset", "0") |> String.to_integer()
      limit = Map.get(params, "limit", "20") |> String.to_integer()

      opts = [offset: offset, limit: limit]

      opts =
        if session_type == "workflow_template" do
          workflow =
            case params["workflow_id"] do
              nil -> nil
              workflow_id -> Workflows.get_workflow(workflow_id)
            end

          Keyword.put(opts, :workflow, workflow)
        else
          opts
        end

      %{sessions: sessions, pagination: pagination} =
        AiAssistant.list_sessions(resource, :desc, opts)

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

  defp validate_session_type(%{"session_type" => session_type})
       when session_type in ["job_code", "workflow_template"] do
    {:ok, session_type}
  end

  defp validate_session_type(_params) do
    {:error, :bad_request}
  end

  defp get_resource("job_code", %{"job_id" => job_id}) do
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

    case Jobs.get_job(job_id) do
      {:ok, job} ->
        check_job_access(job, user)

      {:error, :not_found} ->
        session =
          from(s in ChatSession,
            where: s.session_type == "job_code",
            where:
              s.job_id == ^job_id or
                fragment("? -> 'unsaved_job' ->> 'id' = ?", s.meta, ^job_id),
            limit: 1
          )
          |> Repo.one()

        check_unsaved_job_access(session, user)
    end
  end

  defp authorize_access("workflow_template", project, user) do
    project_user = Projects.get_project_user(project, user)

    case Permissions.can(:workflows, :access_read, user, project_user) do
      :ok -> :ok
      {:error, _reason} -> {:error, :forbidden}
    end
  end

  defp check_job_access(job, user) do
    alias Lightning.Repo

    workflow =
      job.workflow
      |> Repo.preload(project: [:project_users])

    check_workflow_access(workflow, user)
  end

  defp check_unsaved_job_access(nil, _user) do
    :ok
  end

  defp check_unsaved_job_access(
         %{meta: %{"unsaved_job" => %{"workflow_id" => workflow_id}}},
         user
       ) do
    alias Lightning.Repo

    workflow =
      Workflows.get_workflow(workflow_id)
      |> Repo.preload(project: [:project_users])

    check_workflow_access(workflow, user)
  end

  defp check_unsaved_job_access(_, _user), do: :ok

  defp check_workflow_access(workflow, user) do
    project_user =
      Enum.find(workflow.project.project_users, fn pu ->
        pu.user_id == user.id
      end)

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
    end
  end

  defp format_job_code_session(base, session) do
    unsaved_job = session.meta["unsaved_job"]

    cond do
      unsaved_job ->
        workflow = Workflows.get_workflow(unsaved_job["workflow_id"])

        Map.merge(base, %{
          job_name: unsaved_job["name"],
          workflow_name: workflow.name,
          is_unsaved: true
        })

      session.job_id ->
        case Jobs.get_job(session.job_id) do
          {:ok, job} ->
            workflow = Workflows.get_workflow(job.workflow_id)

            Map.merge(base, %{
              job_name: job.name,
              workflow_name: workflow.name
            })

          {:error, :not_found} ->
            Map.merge(base, %{
              job_name: "(deleted job)",
              workflow_name: nil
            })
        end
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
