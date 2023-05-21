defmodule LightningWeb.Components.ProjectDeletionModal do
  @moduledoc false
  use LightningWeb, :component

  use Phoenix.LiveComponent

  alias Lightning.Projects
  alias Lightning.Projects.Project

  @impl true
  def update(%{project: project} = assigns, socket) do
    {:ok,
     socket
     |> assign(
       delete_now?: !is_nil(project.scheduled_deletion),
       scheduled_deletion_changeset: Projects.change_scheduled_deletion(project)
     )
     |> assign(assigns)}
  end

  @impl true
  def handle_event(
        "validate",
        %{"project" => project_params},
        socket
      ) do
    changeset =
      socket.assigns.project
      |> Projects.change_scheduled_deletion(project_params)
      |> Map.put(:action, :validate_scheduled_deletion)

    {:noreply, assign(socket, :scheduled_deletion_changeset, changeset)}
  end

  @impl true
  def handle_event("delete", %{"project" => project_params}, socket) do
    if socket.assigns.delete_now? do
      Projects.delete_project(socket.assigns.project)

      {:noreply,
       socket
       |> put_flash(:info, "Project deleted")
       |> push_patch(to: socket.assigns.return_to)}
    else
      case Projects.schedule_project_deletion(
             socket.assigns.project,
             project_params["scheduled_deletion_name"]
           ) do
        {:ok, %Project{}} ->
          {:noreply,
           socket
           |> put_flash(:info, "Project scheduled for deletion")
           |> push_patch(to: socket.assigns.return_to)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :scheduled_deletion_changeset, changeset)}
      end
    end
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, push_redirect(socket, to: socket.assigns.return_to)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"project-#{@id}"}>
      <PetalComponents.Modal.modal
        max_width="sm"
        title="Delete project"
        close_modal_target={@myself}
      >
        <.form
          :let={f}
          for={@scheduled_deletion_changeset}
          phx-change="validate"
          phx-submit="delete"
          phx-target={@myself}
          id="scheduled_deletion_form"
        >
          <span>
            This project and all data associated to it (workflows, jobs, project users, project credentials, ...) will be deleted. Please make sure none of the workflows in it are still in use.
          </span>

          <div class="hidden sm:block" aria-hidden="true">
            <div class="py-2"></div>
          </div>
          <div class="grid grid-cols-12 gap-12">
            <div class="col-span-8">
              <%= label(f, :scheduled_deletion_name, "Project name",
                class: "block text-sm font-medium text-secondary-700"
              ) %>
              <%= text_input(f, :scheduled_deletion_name,
                class: "block w-full rounded-md",
                phx_debounce: "blur"
              ) %>
              <%= error_tag(f, :scheduled_deletion_name,
                class:
                  "mt-1 focus:ring-primary-500 focus:border-primary-500 block w-full shadow-sm sm:text-sm border-secondary-300 rounded-md"
              ) %>
            </div>
          </div>

          <%= hidden_input(f, :id) %>

          <div class="hidden sm:block" aria-hidden="true">
            <div class="py-5"></div>
          </div>
          <div class="flex justify-end">
            <PetalComponents.Button.button
              label="Cancel"
              phx-click={PetalComponents.Modal.hide_modal(@myself)}
            /> &nbsp;
            <LightningWeb.Components.Common.button
              type="submit"
              color="red"
              phx-disable-with="Deleting..."
              disabled={!@scheduled_deletion_changeset.valid?}
            >
              Delete project
            </LightningWeb.Components.Common.button>
          </div>
        </.form>
      </PetalComponents.Modal.modal>
    </div>
    """
  end
end
