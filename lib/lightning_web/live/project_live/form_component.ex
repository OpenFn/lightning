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

  alias Lightning.Accounts.UserNotifier
  alias Lightning.Projects
  alias Lightning.Repo

  import LightningWeb.Components.Form

  import Ecto.Changeset, only: [fetch_field!: 2]

  @impl true
  def update(
        %{project: project, users: users} = assigns,
        socket
      ) do
    project_users_ids = Enum.map(project.project_users, & &1.user_id)

    users_without_access =
      Enum.reject(users, fn user -> user.id in project_users_ids end)

    p_users_without_access =
      Enum.map(users_without_access, fn user ->
        %Lightning.Projects.ProjectUser{user_id: user.id, user: user, role: nil}
      end)

    all_project_users = project.project_users ++ p_users_without_access

    project_users =
      Enum.sort_by(
        all_project_users,
        fn p_user -> p_user.user.first_name end,
        :asc
      )

    changeset =
      Projects.change_project(%{project | project_users: project_users})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)
     |> assign(:project_users, project_users)
     |> assign(
       :name,
       Projects.url_safe_project_name(fetch_field!(changeset, :name))
     )}
  end

  @impl true
  def handle_event(
        "validate",
        %{"project" => project_params},
        %{assigns: assigns} = socket
      ) do
    # we update the project here so that we can mantain the users in the changeset after validation
    project = %{assigns.project | project_users: assigns.project_users}

    changeset =
      project
      |> Projects.change_project(
        project_params
        |> coerce_raw_name_to_safe_name()
      )
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:changeset, changeset)
     |> assign(:name, fetch_field!(changeset, :name))}
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

    params = Map.merge(project_params, %{"project_users" => users_params})

    save_project(socket, socket.assigns.action, params)
  end

  defp save_project(socket, :edit, project_params) do
    case Projects.update_project(socket.assigns.project, project_params) do
      {:ok, project} ->
        users_to_notify =
          filter_users_to_notify(
            project,
            project_params |> Map.get("project_users", %{})
          )

        notify_project_users(project, users_to_notify)

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
      {:ok, project} ->
        users_to_notify =
          filter_users_to_notify(
            project,
            project_params |> Map.get("project_users", %{})
          )

        notify_project_users(project, users_to_notify)

        {:noreply,
         socket
         |> put_flash(:info, "Project created successfully")
         |> push_patch(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  # TODO: Determine the list of users to notify into the Project context
  # by using the changeset to determine what records are going to be added/removed
  defp filter_users_to_notify(project, project_users_params) do
    project = Repo.preload(project, :project_users)

    existing_project_users =
      project.project_users
      |> Enum.map(fn pu -> pu.user_id end)

    added_project_users =
      project_users_params
      |> Map.values()
      |> Enum.filter(fn pu -> pu["delete"] != "true" end)
      |> Enum.map(fn pu -> pu["user_id"] end)

    added_project_users -- existing_project_users
  end

  defp notify_project_users(project, users_to_notify) do
    users_to_notify
    |> Enum.map(fn user ->
      UserNotifier.deliver_project_addition_notification(
        Lightning.Accounts.get_user!(user),
        project
      )
    end)
  end

  defp coerce_raw_name_to_safe_name(%{"raw_name" => raw_name} = params) do
    new_name = Projects.url_safe_project_name(raw_name)

    params |> Map.put("name", new_name)
  end

  defp coerce_raw_name_to_safe_name(%{} = params) do
    params
  end

  defp full_user_name(user) do
    "#{user.first_name} #{user.last_name}"
  end
end
