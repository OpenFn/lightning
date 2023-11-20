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

  import Ecto.Changeset, only: [fetch_field!: 2, put_assoc: 3]

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
        %Lightning.Projects.ProjectUser{user_id: user.id, user: user}
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

    all_users = users |> Enum.map(&{"#{&1.first_name} #{&1.last_name}", &1.id})

    {:ok,
     socket
     |> assign(assigns |> Map.drop([:users]))
     |> assign(:changeset, changeset)
     |> assign(
       all_users: all_users,
       available_users: filter_available_users(changeset, all_users),
       selected_member: ""
     )
     |> assign(
       :name,
       Projects.url_safe_project_name(fetch_field!(changeset, :name))
     )}
  end

  @impl true
  def handle_event("validate", %{"project" => project_params}, socket) do
    changeset =
      socket.assigns.project
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

  @impl true
  def handle_event("delete_member", %{"index" => index}, socket) do
    index = String.to_integer(index)

    project_users_params =
      fetch_field!(socket.assigns.changeset, :project_users)
      |> Enum.with_index()
      |> Enum.reduce([], fn {pu, i}, project_users ->
        if i == index do
          if is_nil(pu.id) do
            project_users
          else
            [Ecto.Changeset.change(pu, %{delete: true}) | project_users]
          end
        else
          [pu | project_users]
        end
      end)

    changeset =
      socket.assigns.changeset
      |> put_assoc(:project_users, project_users_params)
      |> Map.put(:action, :validate)

    available_users = filter_available_users(changeset, socket.assigns.all_users)

    {:noreply,
     socket |> assign(changeset: changeset, available_users: available_users)}
  end

  @impl true
  def handle_event(
        "select_item",
        %{"id" => user_id},
        socket
      ) do
    {:noreply, socket |> assign(selected_member: user_id)}
  end

  @impl true
  def handle_event(
        "add_new_member",
        %{"userid" => user_id},
        socket
      ) do
    project_users = fetch_field!(socket.assigns.changeset, :project_users)

    project_users =
      Enum.find(project_users, fn pu -> pu.user_id == user_id end)
      |> if do
        project_users
        |> Enum.map(fn pu ->
          if pu.user_id == user_id do
            Ecto.Changeset.change(pu, %{delete: false})
          end
        end)
      else
        project_users
        |> Enum.concat([%Lightning.Projects.ProjectUser{user_id: user_id}])
      end

    changeset =
      socket.assigns.changeset
      |> put_assoc(:project_users, project_users)
      |> Map.put(:action, :validate)

    available_users = filter_available_users(changeset, socket.assigns.all_users)

    {:noreply,
     socket
     |> assign(
       changeset: changeset,
       available_users: available_users,
       selected_member: ""
     )}
  end

  def handle_event("save", %{"project" => project_params}, socket) do
    save_project(socket, socket.assigns.action, project_params)
  end

  defp filter_available_users(changeset, all_users) do
    existing_ids =
      fetch_field!(changeset, :project_users)
      |> Enum.reject(fn pu -> pu.delete end)
      |> Enum.map(fn pu -> pu.user_id end)

    all_users |> Enum.reject(fn {_, user_id} -> user_id in existing_ids end)
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

  defp user_name_for_id(users, user_id) do
    users
    |> Enum.find_value(fn {name, id} ->
      if id == user_id, do: name
    end)
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
