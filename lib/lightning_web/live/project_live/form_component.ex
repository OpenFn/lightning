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

  alias Lightning.Projects
  import LightningWeb.Components.Form
  import LightningWeb.Components.Common

  import Ecto.Changeset, only: [fetch_field!: 2, put_assoc: 3]

  @impl true
  def update(
        %{project: project, users: users} = assigns,
        socket
      ) do
    changeset = Projects.change_project(project)

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
      {:ok, _project} ->
        notify_project_users(project_params |> Map.get("project_users"))
        |> IO.inspect(label: "YOOOOO")

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
        notify_project_users(project_params |> Map.get("project_users"))
        |> IO.inspect(label: "YOOOOO")

        {:noreply,
         socket
         |> put_flash(:info, "Project created successfully")
         |> push_patch(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp notify_project_users(nil), do: nil

  defp notify_project_users(project_users) do
    project_users
    |> Map.values()
    |> Enum.filter(fn pu -> pu["delete"] != "true" end)
    |> IO.inspect()
  end

  defp coerce_raw_name_to_safe_name(%{"raw_name" => raw_name} = params) do
    new_name = Projects.url_safe_project_name(raw_name)

    params |> Map.put("name", new_name)
  end

  defp coerce_raw_name_to_safe_name(%{} = params) do
    params
  end
end
