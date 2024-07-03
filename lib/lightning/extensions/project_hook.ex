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
    Projects.project_runs_query(project) |> Repo.delete_all()

    Projects.project_run_step_query(project) |> Repo.delete_all()

    Projects.project_workorders_query(project) |> Repo.delete_all()

    Projects.project_steps_query(project) |> Repo.delete_all()

    Projects.project_jobs_query(project) |> Repo.delete_all()

    Projects.project_triggers_query(project) |> Repo.delete_all()

    Projects.project_workflows_query(project) |> Repo.delete_all()

    Projects.project_users_query(project) |> Repo.delete_all()

    Projects.project_credentials_query(project) |> Repo.delete_all()

    Projects.project_dataclips_query(project) |> Repo.delete_all()

    Repo.delete(project)
  end
end
