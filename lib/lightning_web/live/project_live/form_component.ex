defmodule LightningWeb.ProjectLive.FormComponent do
  @moduledoc """
  Form Component for working with a single Job

  A Job's `adaptor` field is a combination of the module name and the version.
  It's formatted as an NPM style string.

  The form allows the user to select a module by name and then it's version,
  while the version dropdown itself references `adaptor` directly.

  Meaning the `adaptor_name` dropdown and assigns value is not persisted.
  """
  use LightningWeb, :live_component

  import Ecto.Changeset, only: [fetch_field!: 2]
  import LightningWeb.Components.Form
  alias LightningWeb.Live.Helpers.TableHelpers

  alias Lightning.Helpers
  alias Lightning.Projects
  alias Lightning.Projects.Project

  # Simple helper functions for user data
  defp get_user_name(user) when is_nil(user), do: ""

  defp get_user_name(user),
    do: "#{user.first_name || ""} #{user.last_name || ""}" |> String.trim()

  defp get_user_email(user) when is_nil(user), do: ""
  defp get_user_email(user), do: user.email || ""

  defp get_user_role(form_input) do
    case form_input[:role].value do
      nil -> ""
      role -> to_string(role)
    end
  end

  # Simplified sorting configuration
  defp user_search_fields do
    [
      fn enriched_form -> get_user_name(enriched_form.user) end,
      fn enriched_form -> get_user_email(enriched_form.user) end,
      fn enriched_form -> get_user_role(enriched_form.form) end
    ]
  end

  defp user_sort_map do
    %{
      "name" => fn enriched_form -> get_user_name(enriched_form.user) end,
      "email" => fn enriched_form -> get_user_email(enriched_form.user) end,
      "role" => fn enriched_form -> get_user_role(enriched_form.form) end
    }
  end

  @impl true
  def update(
        %{project: project, users: users} = assigns,
        socket
      ) do
    # Create project_users list with consistent ordering for form stability
    project_users =
      users
      |> Enum.sort_by(fn user -> user.first_name end, :asc)
      |> Enum.map(fn user ->
        existing_project_user =
          Enum.find(project.project_users, fn pu -> pu.user_id == user.id end)

        %{
          id: existing_project_user && existing_project_user.id,
          user_id: user.id,
          role: existing_project_user && existing_project_user.role
        }
      end)

    changeset =
      Project.form_with_users_changeset(
        project,
        %{project_users: project_users, raw_name: project.name}
      )

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)
     |> assign(:sort_key, "name")
     |> assign(:sort_direction, "asc")
     |> assign(:filter, "")
     |> assign(:name, fetch_field!(changeset, :name))}
  end

  @impl true
  def handle_event("validate", %{"project" => project_params}, socket) do
    changeset =
      socket.assigns.project
      |> Project.form_with_users_changeset(project_params)
      |> Helpers.copy_error(:name, :raw_name)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:changeset, changeset)
     |> assign(:name, fetch_field!(changeset, :name))}
  end

  def handle_event("sort", %{"by" => sort_key}, socket) do
    {sort_key, sort_direction} =
      TableHelpers.toggle_sort_direction(
        socket.assigns.sort_direction,
        socket.assigns.sort_key,
        sort_key
      )

    {:noreply,
     assign(socket,
       sort_key: sort_key,
       sort_direction: sort_direction
     )}
  end

  def handle_event("filter", %{"value" => filter}, socket) do
    {:noreply,
     assign(socket,
       filter: filter
     )}
  end

  def handle_event("clear_filter", _params, socket) do
    {:noreply,
     assign(socket,
       filter: ""
     )}
  end

  def handle_event("save", %{"project" => project_params}, socket) do
    # Drop non-persited project users without role
    users =
      Enum.reject(project_params["project_users"] || %{}, fn {_key, params} ->
        is_nil(params["id"]) and params["role"] == ""
      end)

    users_params =
      Enum.map(users, fn {index, params} ->
        if params["role"] == "" do
          {index, Map.merge(params, %{"delete" => "true"})}
        else
          {index, params}
        end
      end)
      |> Enum.into(%{})

    params =
      Map.merge(project_params, %{
        "project_users" => users_params,
        "users_sort" => Map.keys(users_params)
      })

    save_project(
      socket,
      socket.assigns.action,
      Helpers.derive_name_param(params)
    )
  end

  defp save_project(socket, :edit, project_params) do
    case Projects.update_project_with_users(
           socket.assigns.project,
           project_params
         ) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project updated successfully")
         |> push_patch(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Helpers.copy_error(changeset, :name, :raw_name)
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_project(socket, :new, project_params) do
    case Projects.create_project(project_params) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project created successfully")
         |> push_patch(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Helpers.copy_error(changeset, :name, :raw_name)
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp full_user_name(user) do
    "#{user.first_name} #{user.last_name}"
  end

  defp find_user_by_id(users, user_id) do
    Enum.find(users, fn user -> user.id == user_id end)
  end

  defp get_sorted_filtered_forms(f, users, filter, sort_key, sort_direction) do
    forms = Phoenix.HTML.FormData.to_form(f.source, f, :project_users, f.options)

    # Create enriched form data with user info for easier sorting/filtering
    enriched_forms =
      Enum.map(forms, fn form ->
        user = find_user_by_id(users, form[:user_id].value)
        %{form: form, user: user}
      end)

    # Use TableHelpers for consistent filtering and sorting
    sorted_filtered_forms =
      TableHelpers.filter_and_sort(
        enriched_forms,
        filter,
        user_search_fields(),
        sort_key,
        sort_direction,
        user_sort_map()
      )

    # Extract just the forms for the template
    Enum.map(sorted_filtered_forms, fn %{form: form} -> form end)
  end
end
