defmodule LightningWeb.DashboardLive.ProjectCreationModal do
  use LightningWeb, :live_component

  alias Lightning.Helpers
  alias Lightning.Projects
  alias Lightning.Projects.Project

  @impl true
  def update(assigns, socket) do
    project = %Project{}
    changeset = Project.form_changeset(project, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(project: project)
     |> assign(changeset: changeset)
     |> assign(:name, Ecto.Changeset.get_field(changeset, :name))}
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, socket |> push_navigate(to: socket.assigns.return_to)}
  end

  def handle_event("validate", %{"project" => project_params}, socket) do
    changeset =
      socket.assigns.project
      |> Project.form_changeset(project_params)
      |> Helpers.copy_error(:name, :raw_name)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:changeset, changeset)
     |> assign(:name, Ecto.Changeset.fetch_field!(changeset, :name))}
  end

  def handle_event("save", %{"project" => project_params}, socket) do
    %{current_user: current_user, return_to: return_to} = socket.assigns

    project_params
    |> Helpers.derive_name_param()
    |> Map.put_new("project_users", %{
      0 => %{
        "user_id" => current_user.id,
        "role" => "owner"
      }
    })
    |> Projects.create_project(false)
    |> case do
      {:ok, project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project created successfully")
         |> assign(project: project)
         |> push_navigate(to: return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Helpers.copy_error(changeset, :name, :raw_name)
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="text-xs">
      <.modal id={@id} width="xl:min-w-1/3 min-w-1/2 max-w-full">
        <:title>
          <div class="flex justify-between">
            <span class="font-bold">Create a new project</span>
            <button
              id="close-credential-modal-type-picker"
              phx-click="close_modal"
              phx-target={@myself}
              type="button"
              class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
              aria-label={gettext("close")}
            >
              <span class="sr-only">Close</span>
              <.icon name="hero-x-mark" class="h-5 w-5 stroke-current" />
            </button>
          </div>
        </:title>
        <.form
          :let={f}
          for={@changeset}
          id="project-form"
          phx-target={@myself}
          phx-change="validate"
          phx-submit="save"
        >
          <div class="container mx-auto px-6 space-y-6 bg-white">
            <div class="space-y-4">
              <.input type="text" field={f[:raw_name]} label="Name" required="true" />
              <.input type="hidden" field={f[:name]} />
              <small class="mt-2 block text-xs text-gray-600">
                <.name_badge name={@name} field={f[:name]}>
                  Your project will be named
                </.name_badge>
              </small>
            </div>
            <div class="space-y-4">
              <.input
                type="textarea"
                class="bg-white text-slate-900 u"
                field={f[:description]}
                label="Description"
              />
              <small class="mt-2 block text-xs text-gray-600">
                A short description of a project [max 240 characters]
              </small>
            </div>
          </div>
          <.modal_footer>
            <.button
              type="submit"
              theme="primary"
              disabled={!@changeset.valid?}
              phx-target={@myself}
            >
              Create project
            </.button>
            <.button
              id="cancel-project-creation"
              theme="secondary"
              type="button"
              phx-click="close_modal"
              phx-target={@myself}
            >
              Cancel
            </.button>
          </.modal_footer>
        </.form>
      </.modal>
    </div>
    """
  end
end
