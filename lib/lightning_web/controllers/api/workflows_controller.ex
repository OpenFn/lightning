defmodule LightningWeb.API.WorkflowsController do
  use LightningWeb, :controller

  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.Workflows
  alias Lightning.Workflows.Presence
  alias Lightning.Workflows.Workflow
  alias Lightning.Policies.Permissions

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
  end

  defp save_workflow(params, user), do: Workflows.save_workflow(params, user)

  defp save_workflow(workflow, params, user),
    do: workflow |> Workflow.changeset(params) |> Workflows.save_workflow(user)

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
end
