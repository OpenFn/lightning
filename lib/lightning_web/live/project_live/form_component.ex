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

  import Ecto.Changeset, only: [fetch_field!: 2]

  @impl true
  def update(%{project: project, users: users} = assigns, socket) do
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
  def handle_event(
        "select_new_member",
        %{"project" => %{"available_users" => user_id}},
        socket
      ) do
    {:noreply, socket |> assign(:selected_member, user_id)}
  end

  @impl true
  def handle_event("delete_member", %{"index" => index}, socket) do
    index = String.to_integer(index)

    project_users_params =
      fetch_field!(socket.assigns.changeset, :project_users)
      |> Enum.with_index()
      |> Enum.reject(fn {pu, i} ->
        i == index && is_nil(pu.id)
      end)
      |> Enum.map(fn {pu, i} ->
        %{
          "user_id" => pu.user_id,
          "id" => pu.id,
          "delete" => if(i == index, do: "true", else: pu.delete)
        }
      end)

    changeset =
      socket.assigns.project
      |> Projects.change_project(%{"project_users" => project_users_params})
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(changeset: changeset)}
  end

  @impl true
  def handle_event(
        "add_new_member",
        _params,
        socket
      ) do
    project_users_params =
      fetch_field!(socket.assigns.changeset, :project_users)
      |> Enum.map(fn pu -> %{"user_id" => pu.user_id, "id" => pu.id} end)
      |> Enum.concat([%{"user_id" => socket.assigns.selected_member}])

    changeset =
      socket.assigns.project
      |> Projects.change_project(%{"project_users" => project_users_params})
      |> Map.put(:action, :validate)

    available_users = filter_available_users(changeset, socket.assigns.all_users)

    {:noreply,
     socket |> assign(changeset: changeset, available_users: available_users)}
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
    new_name = Projects.url_safe_project_name(raw_name)

    params |> Map.put("name", new_name)
  end

  defp coerce_raw_name_to_safe_name(%{} = params) do
    params
  end
end
