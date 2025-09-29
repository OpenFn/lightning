defmodule Lightning.Extensions.ProjectHook do
  @moduledoc """
  Allows handling user creation or registration atomically without relying on async events.
  """
  @behaviour Lightning.Extensions.ProjectHooking

  alias Ecto.Changeset
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Repo

  import Ecto.Query

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
    Projects.project_jobs_query(project) |> Repo.delete_all()

    # Clean up webhook auth method associations before deleting triggers
    delete_webhook_auth_method_associations(project)
    Projects.project_webhook_auth_methods_query(project) |> Repo.delete_all()

    Projects.project_triggers_query(project) |> Repo.delete_all()
    Projects.project_workflows_query(project) |> Repo.delete_all()
    Projects.project_users_query(project) |> Repo.delete_all()
    Projects.project_credentials_query(project) |> Repo.delete_all()
    Projects.delete_project_dataclips(project)

    Repo.delete(project)
  end

  defp delete_webhook_auth_method_associations(project) do
    # Get all webhook auth method IDs for this project
    wam_ids =
      from(wam in Lightning.Workflows.WebhookAuthMethod,
        where: wam.project_id == ^project.id,
        select: wam.id
      )
      |> Repo.all()
      |> Enum.map(&Ecto.UUID.dump!/1)

    # Clean up the many-to-many join table
    from(j in "trigger_webhook_auth_methods",
      where: j.webhook_auth_method_id in ^wam_ids
    )
    |> Repo.delete_all()
  end

  @spec handle_project_validation(Changeset.t(Project.t())) ::
          Changeset.t(Project.t())
  def handle_project_validation(changeset), do: changeset
end
