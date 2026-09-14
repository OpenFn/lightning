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
    with :ok <- delete_sandboxes(project),
         :ok <- remove_files(project) do
      Projects.delete_project_workorders(project)
      Lightning.Channels.delete_channel_requests_for_project(project)
      Projects.project_jobs_query(project) |> Repo.delete_all()
      Projects.project_triggers_query(project) |> Repo.delete_all()
      Projects.project_workflows_query(project) |> Repo.delete_all()
      Projects.project_users_query(project) |> Repo.delete_all()
      Projects.project_credentials_query(project) |> Repo.delete_all()
      Projects.project_oauth_clients_query(project) |> Repo.delete_all()
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
  end

  # Stored files go first, and nothing destructive happens until they're all
  # gone. `project_files.project_id` doesn't cascade, so a project that has ever
  # been exported can't be deleted while its archives exist — and those archives
  # hold raw dataclip bodies, so dropping the rows without the objects would
  # leave the data in storage with nothing tracking it. Bailing out here keeps
  # the project whole and purgeable on the next attempt.
  defp remove_files(project) do
    case Projects.remove_all_files_for(project) do
      :ok ->
        :ok

      {:error, remaining} ->
        {:error,
         project
         |> Changeset.change()
         |> Changeset.add_error(
           :project_files,
           "#{length(remaining)} stored file(s) could not be deleted from storage"
         )}
    end
  end

  defp delete_sandboxes(project) do
    Projects.list_sandboxes(project.id)
    |> Enum.reduce_while(:ok, fn child_project, :ok ->
      case handle_delete_project(child_project) do
        {:ok, _child} -> {:cont, :ok}
        {:error, _changeset} = error -> {:halt, error}
      end
    end)
  end

  @spec handle_project_validation(Changeset.t(Project.t())) ::
          Changeset.t(Project.t())
  def handle_project_validation(changeset), do: changeset
end
