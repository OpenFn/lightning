defmodule LightningWeb.DashboardLive.ProjectCreationModal do
  use LightningWeb, :live_component

  alias Lightning.Projects
  alias Lightning.Projects.Project

  @impl true
  def update(assigns, socket) do
    project = %Project{}
    changeset = Project.changeset(project, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(project: project)
     |> assign(changeset: changeset)}
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, push_redirect(socket, to: socket.assigns.return_to)}
  end

  def handle_event("validate", %{"project" => project_params}, socket) do
    changeset =
      socket.assigns.project
      |> Project.changeset(
        project_params
        |> coerce_raw_name_to_safe_name
      )
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:changeset, changeset)
     |> assign(:name, Ecto.Changeset.fetch_field!(changeset, :name))}
  end

  def handle_event("save", %{"project" => project_params}, socket) do
    %{current_user: current_user, return_to: return_to} = socket.assigns

    project_params
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
         |> push_redirect(to: return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :project_changeset, changeset)}
    end
  end

  defp coerce_raw_name_to_safe_name(%{"raw_name" => raw_name} = params) do
    new_name = Projects.url_safe_project_name(raw_name)

    params |> Map.put("name", new_name)
  end

  defp coerce_raw_name_to_safe_name(%{} = params) do
    params
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
              <Heroicons.x_mark solid class="h-5 w-5 stroke-current" />
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
                <%= if to_string(f[:name].value) != "" do %>
                  Your project will be named <span class="font-mono border rounded-md p-1 bg-yellow-100 border-slate-300">
      <%= @name %></span>.
                <% end %>
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
          <.modal_footer class="mt-6 mx-6">
            <div class="sm:flex sm:flex-row-reverse">
              <button
                type="submit"
                disabled={!@changeset.valid?}
                phx-target={@myself}
                class="inline-flex w-full justify-center rounded-md disabled:bg-primary-300 bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 sm:ml-3 sm:w-auto"
              >
                Create project
              </button>
              <button
                id="cancel-credential-type-picker"
                type="button"
                phx-click="close_modal"
                phx-target={@myself}
                class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:mt-0 sm:w-auto"
              >
                Cancel
              </button>
            </div>
          </.modal_footer>
        </.form>
      </.modal>
    </div>
    """
  end
end
