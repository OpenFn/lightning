defmodule LightningWeb.API.WorkflowsController do
  use LightningWeb, :controller

  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Policies.Permissions
  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.Services.UsageLimiter
  alias Lightning.Workflows
  alias Lightning.Workflows.Presence
  alias Lightning.Workflows.Workflow

  action_fallback LightningWeb.FallbackController

  require Logger

  def index(conn, %{"project_id" => project_id}) do
    with :ok <- authorize_read(conn, project_id) do
      list =
        Workflows.list_project_workflows(project_id,
          include: [:edges, :jobs, :triggers]
        )

      json(conn, %{workflows: list, error: nil})
    end
  end

  def create(conn, %{"project_id" => project_id} = params) do
    with :ok <- authorize_write(conn, project_id),
         {:ok, %{id: workflow_id}} <-
           save_workflow(params, conn.assigns.current_resource) do
      json(conn, %{id: workflow_id, error: nil})
    end
    |> then(&maybe_handle_error(conn, &1))
  end

  def show(conn, %{"project_id" => project_id, "id" => workflow_id}) do
    with :ok <- authorize_read(conn, project_id),
         {:ok, workflow} <- get_workflow(workflow_id, project_id) do
      json(conn, %{workflow: workflow, error: nil})
    end
  end

  def update(conn, %{"project_id" => project_id, "id" => workflow_id} = params) do
    with :ok <- authorize_write(conn, project_id),
         {:ok, workflow} <- get_workflow(workflow_id, project_id),
         :ok <- authorize_write(conn, workflow),
         {:ok, %{id: workflow_id}} <-
           save_workflow(workflow, params, conn.assigns.current_resource) do
      json(conn, %{id: workflow_id, error: nil})
    end
    |> then(&maybe_handle_error(conn, &1, workflow_id))
  end

  defp save_workflow(%{"project_id" => project_id} = params, user) do
    active_triggers_count =
      params
      |> Map.get("triggers", [])
      |> Enum.count(& &1["enabled"])

    cond do
      active_triggers_count > 1 ->
        {:error, :too_many_active_triggers}

      :else ->
        save_workflow(params, active_triggers_count > 0, project_id, user)
    end
  end

  defp save_workflow(%{triggers: triggers} = workflow, params, user) do
    changes_triggers? = Map.has_key?(params, "triggers")

    triggers_ids =
      params
      |> Map.get("triggers", [])
      |> Enum.map(& &1["id"])

    active_triggers_count =
      params
      |> Map.get("triggers", [])
      |> Enum.count(& &1["enabled"])

    cond do
      changes_triggers? and Enum.any?(triggers, &(&1.id not in triggers_ids)) ->
        {:error, :cannot_replace_trigger}

      active_triggers_count > 1 ->
        {:error, :too_many_active_triggers}

      :else ->
        workflow
        |> Workflows.change_workflow(params)
        |> save_workflow(active_triggers_count > 0, workflow.project_id, user)
    end
  end

  defp save_workflow(params_or_changeset, active?, project_id, user)
       when is_boolean(active?) do
    if not active? or
         :ok ==
           UsageLimiter.limit_action(
             %Action{type: :activate_workflow},
             %Context{project_id: project_id}
           ) do
      Workflows.save_workflow(params_or_changeset, user)
    else
      {:error, :too_many_workflows}
    end
  end

  defp get_workflow(workflow_id, project_id) do
    case Workflows.get_workflow(workflow_id, include: [:edges, :jobs, :triggers]) do
      nil -> {:error, :not_found}
      %{project_id: ^project_id} = workflow -> {:ok, workflow}
      _project_mismatch -> {:error, :bad_request}
    end
  end

  defp authorize_write(_conn, %Workflow{} = workflow) do
    if Presence.has_any_presence?(workflow) do
      {:error, :conflict}
    else
      :ok
    end
  end

  defp authorize_write(conn, project_id) do
    authorize_for_project(conn, project_id, :access_write)
  end

  defp authorize_read(conn, project_id) do
    authorize_for_project(conn, project_id, :access_read)
  end

  defp authorize_for_project(conn, project_id, access) do
    project = Repo.get(Project, project_id)

    Permissions.can(
      Lightning.Policies.Workflows,
      access,
      conn.assigns.current_resource,
      project
    )
  end

  defp maybe_handle_error(conn, result, workflow_id \\ nil) do
    case result do
      {:error, :cannot_replace_trigger} ->
        reply_422(
          conn,
          workflow_id,
          "The triggers cannot be replaced, only edited or added."
        )

      {:error, :too_many_workflows} ->
        reply_422(
          conn,
          workflow_id,
          "Your plan has reached the limit of active workflows."
        )

      {:error, :too_many_active_triggers} ->
        reply_422(
          conn,
          workflow_id,
          "A workflow can have only one trigger enabled at a time."
        )

      result ->
        result
    end
  end

  defp reply_422(conn, workflow_id, msg) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{id: workflow_id, error: msg})
  end
end
