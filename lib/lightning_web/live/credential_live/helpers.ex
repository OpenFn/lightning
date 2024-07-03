defmodule LightningWeb.CredentialLive.Helpers do
  @moduledoc """
  This module provides helper functions for managing project associations
  within credential live views, allowing dynamic assignment and update
  of projects associations to credentials and / or oauth clients.
  """

  defp build_project_assoc_map(
         %{id: id, project_id: project_id},
         extra_fields \\ %{}
       ) do
    Map.merge(
      %{
        "id" => id,
        "project_id" => project_id
      },
      extra_fields
    )
  end

  @doc """
  Prepares a list of projects to be associated, updated, or removed based on the selected input.

  ## Parameters
  - `changeset`: The changeset from which projects are fetched.
  - `selected_projects`: A list of currently selected projects.
  - `assoc_key`: The key in the changeset data containing project associations.

  ## Returns
  - A list of maps representing the projects to be deleted, added, or kept.
  """
  def prepare_projects_associations(changeset, selected_projects, assoc_key) do
    project_credentials = Ecto.Changeset.fetch_field!(changeset, assoc_key)
    selected_ids = MapSet.new(Enum.map(selected_projects, & &1.id))
    project_ids = MapSet.new(Enum.map(project_credentials, & &1.project_id))

    {projects_to_keep, projects_to_delete} =
      Enum.split_with(
        project_credentials,
        &MapSet.member?(selected_ids, &1.project_id)
      )

    projects_to_delete =
      Enum.map(
        projects_to_delete,
        &build_project_assoc_map(&1, %{"delete" => "true"})
      )

    projects_to_keep = Enum.map(projects_to_keep, &build_project_assoc_map(&1))

    projects_to_add =
      selected_ids
      |> MapSet.difference(project_ids)
      |> Enum.map(fn id -> %{"project_id" => id} end)

    projects_to_delete ++ projects_to_add ++ projects_to_keep
  end

  @doc """
  Filters available projects to exclude any that are already selected.

  ## Parameters
  - `all_projects`: A list of all projects.
  - `selected_projects`: A list of currently selected projects.

  ## Returns
  - A list of projects that are not selected.
  """
  def filter_available_projects(all_projects, []) do
    all_projects
  end

  def filter_available_projects(all_projects, selected_projects) do
    existing_ids =
      selected_projects |> Enum.map(& &1.id) |> MapSet.new()

    Enum.reject(all_projects, fn %{id: project_id} ->
      MapSet.member?(existing_ids, project_id)
    end)
  end

  @doc """
  Selects a project to be added to the list of selected projects.

  ## Parameters
  - `project_id`: The ID of the project to select.
  - `projects`: All available projects.
  - `available_projects`: Projects that are available for selection.
  - `selected_projects`: Currently selected projects.

  ## Returns
  - A map with the updated lists of selected and available projects.
  """
  def select_project(project_id, projects, available_projects, selected_projects) do
    un_changed = %{
      selected_projects: selected_projects,
      available_projects: available_projects
    }

    case Enum.find(available_projects, fn project -> project_id == project.id end) do
      nil ->
        un_changed

      selected ->
        if Enum.any?(selected_projects, fn project ->
             project.id == selected.id
           end) do
          un_changed
        else
          new_selected_projects = selected_projects ++ [selected]

          new_available_projects =
            filter_available_projects(projects, new_selected_projects)

          %{
            selected_projects: new_selected_projects,
            available_projects: new_available_projects
          }
        end
    end
  end

  @doc """
  Unselects a project from the list of selected projects.

  ## Parameters
  - `project_id`: The ID of the project to unselect.
  - `projects`: All projects available.
  - `selected_projects`: Currently selected projects.

  ## Returns
  - A map with the updated lists of selected and available projects.
  """
  def unselect_project(project_id, projects, selected_projects) do
    new_selected_projects =
      selected_projects
      |> Enum.reject(fn project -> project_id == project.id end)

    new_available_projects =
      filter_available_projects(projects, new_selected_projects)

    %{
      selected_projects: new_selected_projects,
      available_projects: new_available_projects
    }
  end

  def handle_save_response(socket, credential) do
    if socket.assigns[:on_save] do
      socket.assigns[:on_save].(credential)
      Phoenix.LiveView.push_event(socket, "close_modal", %{})
    else
      socket
      |> Phoenix.LiveView.put_flash(:info, "Credential created successfully")
      |> Phoenix.LiveView.push_redirect(to: socket.assigns.return_to)
    end
  end
end
