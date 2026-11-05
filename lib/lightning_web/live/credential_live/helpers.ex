defmodule LightningWeb.CredentialLive.Helpers do
  @moduledoc """
  This module provides helper functions for managing project associations
  within credential live views, allowing dynamic assignment and update
  of projects associations to credentials and / or oauth clients.
  """

  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.OauthClient
  alias LightningWeb.Live.Helpers.TableHelpers

  @table_params ~w(q
    credentials_page credentials_sort credentials_dir
    keychain_page keychain_sort keychain_dir
    oauth_clients_page oauth_clients_sort oauth_clients_dir
  )

  @page_params ~w(credentials_page keychain_page oauth_clients_page)

  @sortable_columns %{
    "credentials" => [:name, :type, :owner],
    "keychain" => [:name, :path, :owner],
    "oauth_clients" => [:name, :owner]
  }

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
    selected_ids = MapSet.new(selected_projects, & &1.id)
    project_ids = MapSet.new(project_credentials, & &1.project_id)

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

  @doc """
  The `project_credentials` to pre-select when creating a credential: only the
  active project. Empty when there is no project context.
  """
  @spec default_project_credentials(Lightning.Projects.Project.t() | nil) ::
          [Lightning.Projects.ProjectCredential.t()]
  def default_project_credentials(nil), do: []

  def default_project_credentials(%Lightning.Projects.Project{id: id}) do
    [%Lightning.Projects.ProjectCredential{project_id: id}]
  end

  def handle_save_response(socket, credential) do
    if socket.assigns[:on_save] do
      socket.assigns[:on_save].(credential)
      Phoenix.LiveView.push_event(socket, "close_modal", %{})
    else
      socket
      |> Phoenix.LiveView.put_flash(:info, "Credential created successfully")
      |> Phoenix.LiveView.push_navigate(to: socket.assigns.return_to)
    end
  end

  @doc """
  Picks the search, sort and page params the credentials tables use out of a
  LiveView's params.
  """
  @spec table_params(map()) :: map()
  def table_params(params) do
    params
    |> Map.take(@table_params)
    |> Map.filter(fn {_key, value} -> is_binary(value) and value != "" end)
  end

  @doc """
  The page params for one table: `"credentials"`, `"keychain"` or
  `"oauth_clients"`.
  """
  @spec page_params(map(), String.t()) :: map()
  def page_params(table_params, table) do
    %{"page" => table_params["#{table}_page"] || "1"}
  end

  @doc """
  The `:search` and `:order_by` options for one table. The sort column is
  resolved against an allow-list, so an unknown value falls back to the name.
  """
  @spec list_opts(map(), String.t()) :: keyword()
  def list_opts(table_params, table) do
    field =
      TableHelpers.sort_field(
        table_params["#{table}_sort"],
        Map.fetch!(@sortable_columns, table),
        :name
      )

    direction = TableHelpers.sort_direction(table_params["#{table}_dir"])

    [search: table_params["q"] || "", order_by: {field, direction}]
  end

  @doc """
  Builds the pagination URL function for one table. It keeps every other param,
  so changing page doesn't lose the search, the sort or another table's page.
  """
  @spec page_url(function(), map(), String.t()) :: function()
  def page_url(table_path, table_params, table) do
    fn opts ->
      table_path.(Map.put(table_params, "#{table}_page", opts[:page]))
    end
  end

  @doc """
  Sets the search term and sends every table back to its first page.
  """
  @spec search_params(map(), String.t()) :: map()
  def search_params(table_params, search) do
    table_params
    |> Map.drop(@page_params)
    |> Map.put("q", String.trim(search))
    |> table_params()
  end

  @doc """
  Sorts one table by `sort_key`, or flips the direction if it's already sorted
  by that column, and sends that table back to its first page.
  """
  @spec sort_params(map(), String.t(), String.t()) :: map()
  def sort_params(table_params, table, sort_key) do
    {sort_key, direction} =
      TableHelpers.toggle_sort_direction(
        table_params["#{table}_dir"] || "asc",
        table_params["#{table}_sort"] || "name",
        sort_key
      )

    table_params
    |> Map.delete("#{table}_page")
    |> Map.merge(%{"#{table}_sort" => sort_key, "#{table}_dir" => direction})
  end

  @spec empty_page() :: Scrivener.Page.t()
  def empty_page do
    %Scrivener.Page{
      entries: [],
      page_number: 1,
      page_size: 0,
      total_entries: 0,
      total_pages: 1
    }
  end

  @doc """
  Fills in the `project_names` and `environment_names` the credentials table
  displays, for every credential on the page.
  """
  @spec with_credential_display_fields(Scrivener.Page.t()) ::
          Scrivener.Page.t()
  def with_credential_display_fields(%Scrivener.Page{} = page) do
    %{page | entries: Enum.map(page.entries, &credential_display_fields/1)}
  end

  @doc """
  Fills in the `project_names` the OAuth clients table displays, labelling
  global clients as `GLOBAL`.
  """
  @spec with_oauth_client_display_fields(Scrivener.Page.t()) ::
          Scrivener.Page.t()
  def with_oauth_client_display_fields(%Scrivener.Page{} = page) do
    %{page | entries: Enum.map(page.entries, &oauth_client_display_fields/1)}
  end

  defp credential_display_fields(%Credential{} = credential) do
    %{
      credential
      | project_names: Enum.map(credential.projects, & &1.name),
        environment_names: Enum.map(credential.credential_bodies, & &1.name)
    }
  end

  defp oauth_client_display_fields(%OauthClient{global: true} = client),
    do: %{client | project_names: ["GLOBAL"]}

  defp oauth_client_display_fields(%OauthClient{} = client),
    do: %{client | project_names: Enum.map(client.projects, & &1.name)}
end
