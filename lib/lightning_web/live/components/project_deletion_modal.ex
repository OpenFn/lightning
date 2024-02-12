defmodule LightningWeb.Components.ProjectDeletionModal do
  @moduledoc false
  use LightningWeb, :component

  use Phoenix.LiveComponent

  alias Lightning.Projects

  @impl true
  def update(%{project: project} = assigns, socket) do
    {:ok,
     socket
     |> assign(deletion_changeset: Projects.validate_for_deletion(project, %{}))
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
      |> Projects.validate_for_deletion(project_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :deletion_changeset, changeset)}
  end

  @impl true
  def handle_event("delete", %{"project" => project_params}, socket) do
    changeset =
      socket.assigns.project
      |> Projects.validate_for_deletion(project_params)
      |> Map.put(:action, :validate)

    if changeset.valid? do
      delete_project(socket.assigns.project)
      |> case do
        {:deleted, _project} ->
          {:noreply,
           socket
           |> put_flash(:info, "Project deleted")
           |> push_navigate(to: socket.assigns.save_return_to)}

        {:scheduled, _project} ->
          {:noreply,
           socket
           |> put_flash(:info, "Project scheduled for deletion")
           |> push_navigate(to: socket.assigns.save_return_to)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :deletion_changeset, changeset)}
      end
    else
      {:noreply, assign(socket, deletion_changeset: changeset)}
    end
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, push_redirect(socket, to: socket.assigns.cancel_return_to)}
  end

  # TODO: This should be moved into the Projects module
  defp delete_project(project) do
    if project.scheduled_deletion do
      Projects.delete_project(project)
      |> case do
        {:ok, project} ->
          {:deleted, project}

        any ->
          any
      end
    else
      Projects.schedule_project_deletion(project)
      |> case do
        {:ok, project} ->
          {:scheduled, project}

        any ->
          any
      end
    end
  end

  defp human_readable_grace_period do
    grace_period = Application.get_env(:lightning, :purge_deleted_after_days)
    if grace_period > 0, do: "#{grace_period} day(s) from today", else: "today"
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
        <.p>
          Enter the project name to confirm it's deletion
        </.p>
        <div class="hidden sm:block" aria-hidden="true">
          <div class="py-2"></div>
        </div>
        <.p>
          Deleting this project will disable access
          for all users, and disable all jobs in the project. The whole project will be deleted
          along with all workflows and work order history, <%= human_readable_grace_period() %>.
        </.p>
        <div class="hidden sm:block" aria-hidden="true">
          <div class="py-2"></div>
        </div>
        <.form
          :let={f}
          for={@deletion_changeset}
          phx-change="validate"
          phx-submit="delete"
          phx-target={@myself}
          id="scheduled_deletion_form"
        >
          <div class="grid grid-cols-12 gap-12">
            <div class="col-span-8">
              <%= Phoenix.HTML.Form.label(f, :name_confirmation, "Project name",
                class: "block text-sm font-medium text-secondary-700"
              ) %>
              <%= Phoenix.HTML.Form.text_input(f, :name_confirmation,
                class: "block w-full rounded-md",
                phx_debounce: "blur"
              ) %>
              <.old_error field={f[:name_confirmation]} />
            </div>
          </div>

          <%= Phoenix.HTML.Form.hidden_input(f, :id) %>
          <%= Phoenix.HTML.Form.hidden_input(f, :name) %>

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
              disabled={!@deletion_changeset.valid?}
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
