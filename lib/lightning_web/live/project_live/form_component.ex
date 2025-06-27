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

  alias Lightning.Helpers
  alias Lightning.Projects
  alias Lightning.Projects.Project

  @impl true
  def update(
        %{project: project, users: users} = assigns,
        socket
      ) do
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
      Project.project_with_users_changeset(
        project,
        %{project_users: project_users}
      )

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)
     |> assign(:sort_key, "name")
     |> assign(:sort_direction, "asc")
     |> assign(:filter, "")
     |> assign(
       :name,
       Helpers.url_safe_name(fetch_field!(changeset, :name))
     )}
  end

  @impl true
  def handle_event("validate", %{"project" => project_params}, socket) do
    changeset =
      socket.assigns.project
      |> Project.project_with_users_changeset(
        project_params
        |> coerce_raw_name_to_safe_name()
      )
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:changeset, changeset)
     |> assign(:name, fetch_field!(changeset, :name))}
  end

  def handle_event("sort", %{"by" => sort_key}, socket) do
    {sort_key, sort_direction} =
      case socket.assigns do
        %{sort_key: ^sort_key, sort_direction: "asc"} ->
          {sort_key, "desc"}

        %{sort_key: ^sort_key, sort_direction: "desc"} ->
          {sort_key, "asc"}

        _ ->
          {sort_key, "asc"}
      end

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

    save_project(socket, socket.assigns.action, params)
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
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp coerce_raw_name_to_safe_name(%{"raw_name" => raw_name} = params) do
    new_name = Helpers.url_safe_name(raw_name)

    params |> Map.put("name", new_name)
  end

  defp coerce_raw_name_to_safe_name(%{} = params) do
    params
  end

  defp full_user_name(user) do
    "#{user.first_name} #{user.last_name}"
  end

  defp find_user_by_id(users, user_id) do
    Enum.find(users, fn user -> user.id == user_id end)
  end

  defp passes_filter?(_user, _form, "") do
    true
  end

  defp passes_filter?(user, form, filter) do
    if user do
      filter_lower = String.downcase(filter)

      String.contains?(
        String.downcase("#{user.first_name} #{user.last_name}"),
        filter_lower
      ) ||
        String.contains?(String.downcase(user.email || ""), filter_lower) ||
        String.contains?(
          String.downcase(to_string(form[:role].value || "")),
          filter_lower
        )
    else
      false
    end
  end

  defp get_sorted_filtered_forms(f, users, filter, sort_key, sort_direction) do
    forms = Phoenix.HTML.FormData.to_form(f.source, f, :project_users, f.options)

    forms
    |> Enum.filter(fn form ->
      passes_filter?(find_user_by_id(users, form[:user_id].value), form, filter)
    end)
    |> Enum.sort_by(
      fn form ->
        user = find_user_by_id(users, form[:user_id].value)
        user_name = (user && "#{user.first_name} #{user.last_name}") || ""
        user_role = to_string(form[:role].value || "")

        case sort_key do
          "name" -> user_name
          "email" -> (user && user.email) || ""
          "role" -> user_role
          "no_access" -> {user_role == "", user_name}
          "owner" -> {user_role != "owner", user_name}
          "admin" -> {user_role != "admin", user_name}
          "editor" -> {user_role != "editor", user_name}
          "viewer" -> {user_role != "viewer", user_name}
          _ -> user_name
        end
      end,
      case sort_direction do
        "asc" -> &<=/2
        "desc" -> &>=/2
      end
    )
  end
end
