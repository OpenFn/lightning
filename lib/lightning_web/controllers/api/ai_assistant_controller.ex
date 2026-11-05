defmodule LightningWeb.API.AiAssistantController do
  @moduledoc """
  API endpoints for AI Assistant functionality.
  """
  use LightningWeb, :controller

  import Ecto.Changeset

  alias Lightning.AiAssistant
  alias Lightning.Jobs
  alias Lightning.Workflows
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Channels.AiAssistantJSON

  action_fallback FallbackController

  @session_types ["job_code", "workflow_template"]

  @access_project {:project_users, :access_project}

  @params %{
    session_type: :string,
    job_id: :string,
    project_id: :string,
    workflow_id: Ecto.UUID,
    offset: :integer,
    limit: :integer
  }

  @doc """
  List AI Assistant sessions for a given context (job or project).

  ## Parameters
  - `session_type`: "job_code" or "workflow_template" (required)
  - `job_id`: Job ID (required if session_type is "job_code")
  - `project_id`: Project ID (required if session_type is "workflow_template")
  - `workflow_id`: narrows "workflow_template" sessions to one workflow
  - `offset`: Pagination offset (optional, default: 0)
  - `limit`: Pagination limit (optional, default: 20)

  The project the query names is the target, unless `session_type` is
  "job_code". It is authorised before the other parameters are read,
  `session_type` among them, and a caller with no standing on it gets 403. A
  `job_id` is a filter instead: a job the caller may not see lists no sessions,
  as an unknown one does, and only a `job_id` that isn't a UUID is refused.
  Every bad parameter is reported in one 400 `invalid_parameter`.

  ## Examples
  - GET /api/ai_assistant/sessions?session_type=job_code&job_id=123
  - GET /api/ai_assistant/sessions?session_type=workflow_template&project_id=456
  """
  def list_sessions(conn, params) do
    changeset = cast_params(params)

    with {:ok, target} <- target(changeset),
         {:ok, resource} <- authorize(target, conn.assigns.current_user),
         {:ok, query} <-
           changeset
           |> apply_action(:validate)
           |> Errors.refuse_parameters() do
      %{sessions: sessions, pagination: pagination} = sessions(resource, query)

      json(conn, %{
        sessions: AiAssistantJSON.format_sessions(sessions),
        pagination: %{
          total_count: pagination.total_count,
          has_next_page: pagination.has_next_page,
          has_prev_page: pagination.has_prev_page
        }
      })
    end
  end

  defp cast_params(params) do
    {%{offset: 0, limit: 20, workflow_id: nil}, @params}
    |> cast(params, Map.keys(@params))
    |> validate_required([:session_type])
    |> validate_inclusion(:session_type, @session_types)
    |> validate_target_id()
    |> validate_number(:offset, greater_than_or_equal_to: 0)
    |> validate_number(:limit, greater_than: 0)
  end

  defp validate_target_id(changeset) do
    case get_change(changeset, :session_type) do
      "job_code" -> validate_required(changeset, [:job_id])
      "workflow_template" -> validate_required(changeset, [:project_id])
      _other -> changeset
    end
  end

  # A project_id is the target whatever else the query says, unless the session
  # type asks for a job. With no target named there is nothing to authorise, so
  # every bad parameter is reported at once.
  defp target(%{changes: %{session_type: "job_code", job_id: job_id}}),
    do: {:ok, {:job_code, job_id}}

  defp target(%{changes: %{session_type: "job_code"}} = changeset),
    do: {:error, Errors.parameters(changeset)}

  defp target(%{changes: %{project_id: id}}),
    do: {:ok, {:workflow_template, {{:parameter, "project_id"}, id}}}

  defp target(changeset), do: {:error, Errors.parameters(changeset)}

  defp sessions(:none, _query),
    do: %{
      sessions: [],
      pagination: %{total_count: 0, has_next_page: false, has_prev_page: false}
    }

  defp sessions(resource, query),
    do: AiAssistant.list_sessions(resource, :desc, list_opts(query))

  defp list_opts(%{session_type: "workflow_template"} = query) do
    workflow = query.workflow_id && Workflows.get_workflow(query.workflow_id)
    [offset: query.offset, limit: query.limit, workflow: workflow]
  end

  defp list_opts(query), do: [offset: query.offset, limit: query.limit]

  defp authorize({:workflow_template, project_id}, user),
    do: Target.project(user, project_id, @access_project)

  defp authorize({:job_code, job_id}, user) do
    with {:ok, job_id} <- Request.id({{:parameter, "job_id"}, job_id}) do
      case authorize_job(job_id, user) do
        :ok -> {:ok, job_id}
        {:error, _refused} -> {:ok, :none}
      end
    end
  end

  defp authorize_job(job_id, user) do
    case Jobs.get_job(job_id, include: [:workflow]) do
      {:ok, job} -> authorize_workflow(job.workflow, user)
      {:error, :not_found} -> authorize_unsaved_job(job_id, user)
    end
  end

  defp authorize_unsaved_job(job_id, user) do
    session = AiAssistant.unsaved_job_session(job_id)

    case session do
      # No matching session: listing returns nothing, so allowing is safe.
      nil ->
        :ok

      %{meta: %{"unsaved_job" => %{"workflow_id" => workflow_id}}} ->
        case Workflows.get_workflow(workflow_id) do
          nil -> owner_only(session, user)
          workflow -> authorize_workflow(workflow, user)
        end

      session ->
        owner_only(session, user)
    end
  end

  defp owner_only(%{user_id: user_id}, %{id: user_id}), do: :ok
  defp owner_only(_session, _user), do: {:error, :no_standing}

  defp authorize_workflow(workflow, user) do
    with {:ok, _project} <-
           Target.project(user, workflow, @access_project),
         do: :ok
  end
end
