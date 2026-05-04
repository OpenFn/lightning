defmodule Lightning.Extensions.ProjectHook do
  @moduledoc """
  Allows handling user creation or registration atomically without relying on async events.
  """
  @behaviour Lightning.Extensions.ProjectHooking

  alias Ecto.Changeset
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Repo

  @spec handle_create_project(map()) ::
          {:ok, Project.t()} | {:error, Changeset.t()}
  def handle_create_project(attrs) do
    %Project{}
    |> Project.project_with_users_changeset(attrs)
    |> Repo.insert()
  end

  @spec handle_delete_project(Project.t()) ::
          {:ok, Project.t()} | {:error, Changeset.t()}
  def handle_delete_project(project) do
    Projects.list_sandboxes(project.id)
    |> Enum.each(fn child_project ->
      handle_delete_project(child_project)
    end)

    Projects.delete_project_workorders(project)
    Lightning.Channels.delete_channel_requests_for_project(project)
    Projects.project_jobs_query(project) |> Repo.delete_all()
    Projects.project_triggers_query(project) |> Repo.delete_all()
    Projects.project_workflows_query(project) |> Repo.delete_all()
    Projects.project_users_query(project) |> Repo.delete_all()
    Projects.project_credentials_query(project) |> Repo.delete_all()
    Projects.delete_project_dataclips(project)

    project
    |> Repo.delete()
    |> tap(fn
      {:ok, %Project{parent_id: parent_id}} when not is_nil(parent_id) ->
        Lightning.Projects.SandboxPromExPlugin.fire_sandbox_deleted_event()

      _ ->
        :ok
    end)
  end

  @spec handle_project_validation(Changeset.t(Project.t())) ::
          Changeset.t(Project.t())
  def handle_project_validation(changeset), do: changeset
end
