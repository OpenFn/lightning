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
    {:noreply, push_navigate(socket, to: socket.assigns.cancel_return_to)}
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
    grace_period = Lightning.Config.purge_deleted_after_days()
    if grace_period > 0, do: "#{grace_period} day(s) from today", else: "today"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.modal id={"project-#{@id}"} show={true} width="max-w-md">
      <:title>
        <div class="flex justify-between">
          <span class="font-bold">
            Delete project
          </span>

          <button
            phx-click="close_modal"
            phx-target={@myself}
            type="button"
            class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
            aria-label={gettext("close")}
          >
            <span class="sr-only">Close</span>
            <Heroicons.x_mark solid class="h-5 w-5 stroke-current" />
          </button>
        </div>
      </:title>
      <.form
        :let={f}
        for={@deletion_changeset}
        phx-change="validate"
        phx-submit="delete"
        phx-target={@myself}
        id="scheduled_deletion_form"
      >
        <div class="px-6">
          <p>
            Enter the project name to confirm it's deletion
          </p>

          <p class="mt-2">
            Deleting this project will disable access
            for all users, and disable all jobs in the project. The whole project will be deleted
            along with all workflows and work order history, <%= human_readable_grace_period() %>.
          </p>

          <div class="grid grid-cols-12 gap-12">
            <div class="col-span-8">
              <.input
                type="text"
                field={f[:name_confirmation]}
                label="Project name"
                phx-debounce="blur"
              />
            </div>
          </div>
          <.input type="hidden" field={f[:id]} />
          <.input type="hidden" field={f[:name]} />
        </div>
        <div class="flex-grow bg-gray-100 h-0.5 my-[16px]"></div>
        <div class="flex flex-row-reverse gap-4 mx-6">
          <.button
            id={"project-#{@id}_confirm_button"}
            type="submit"
            color_class="bg-red-600 hover:bg-red-700 text-white"
            phx-disable-with="Deleting..."
            disabled={!@deletion_changeset.valid?}
          >
            Delete project
          </.button>
          <button
            type="button"
            phx-click="close_modal"
            phx-target={@myself}
            class="inline-flex items-center rounded-md bg-white px-3.5 py-2.5 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
          >
            Cancel
          </button>
        </div>
      </.form>
    </.modal>
    """
  end
end
