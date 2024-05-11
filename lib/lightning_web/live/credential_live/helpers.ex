defmodule LightningWeb.CredentialLive.Helpers do
  def prepare_projects_associations(changeset, selected_projects, assoc_key) do
    project_credentials = Ecto.Changeset.fetch_field!(changeset, assoc_key)

    selected_projects_ids =
      Enum.map(selected_projects, fn project -> project.id end)

    projects_to_delete =
      project_credentials
      |> Enum.filter(fn poc -> poc.project_id not in selected_projects_ids end)
      |> Enum.map(fn poc ->
        %{
          "id" => poc.id,
          "project_id" => poc.project_id,
          "delete" => "true"
        }
      end)

    projects_to_keep =
      project_credentials
      |> Enum.filter(fn poc -> poc.project_id in selected_projects_ids end)
      |> Enum.map(fn poc ->
        %{
          "id" => poc.id,
          "project_id" => poc.project_id
        }
      end)

    projects_to_add =
      selected_projects_ids
      |> Enum.reject(fn id ->
        id in Enum.map(project_credentials, & &1.project_id)
      end)
      |> Enum.map(fn id -> %{"project_id" => id} end)

    projects_to_delete ++ projects_to_add ++ projects_to_keep
  end

  def filter_available_projects(all_projects, []) do
    all_projects
  end

  def filter_available_projects(all_projects, selected_projects) do
    existing_ids = Enum.map(selected_projects, fn project -> project.id end)

    Enum.reject(all_projects, fn %{id: project_id} ->
      project_id in existing_ids
    end)
  end

  def select_project(
        %{
          assigns: %{
            available_projects: available_projects,
            selected_projects: selected_projects,
            projects: projects
          }
        } = socket,
        project_id
      ) do
    selected =
      Enum.find(available_projects, fn project -> project_id == project.id end)

    selected_projects = selected_projects ++ [selected]

    available_projects =
      filter_available_projects(
        projects,
        selected_projects
      )

    Phoenix.Component.assign(socket,
      available_projects: available_projects,
      selected_projects: selected_projects,
      selected_project: nil
    )
  end

  def unselect_project(
        %{
          assigns: %{
            selected_projects: selected_projects,
            projects: projects
          }
        } = socket,
        project_id
      ) do
    selected =
      Enum.find(selected_projects, fn project -> project_id == project.id end)

    selected_projects =
      Enum.reject(selected_projects, fn project -> project.id == selected.id end)

    available_projects =
      filter_available_projects(
        projects,
        selected_projects
      )

    Phoenix.Component.assign(socket,
      available_projects: available_projects,
      selected_projects: selected_projects
    )
  end
end
