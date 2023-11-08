defmodule LightningWeb.WorkflowLive.Form do
  use LightningWeb, :live_component
  import WorkflowLive.Modal

  import Ecto.Changeset
  alias Lightning.Workflows
  @form_fields %{name: nil, project_id: nil}
  @types %{name: :string, project_id: :string}

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        :let={f}
        for={@form}
        phx-change="validate"
        phx-submit="create_work_flow"
        phx-target={@myself}
        class="w-11/12 mx-auto"
      >
        <.input
          field={f[:name]}
          type="text"
          label="Workflow Name"
          name="workflow_name"
        />
        <%= inspect(@form.source.valid?) %>
        <.modal_footer>
          <div class="flex gap-x-5 justify-end relative">
            <.link
              class="justify-center rounded-md bg-white px-4 py-3 text-sm font-semibold text-gray-500 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:mt-0 sm:w-auto"
              phx-click={WorkflowLive.Modal.hide_modal("workflow_modal")}
            >
              Cancel
            </.link>
            <span class="group">
              <button
                disabled={@isButtonDisabled}
                type="submit"
                class=" justify-center rounded-md bg-primary-600 disabled:bg-primary-300 px-6 py-3 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 disabled:outline-0 focus:outline-2 focus:outline-indigo-600 focus:outline-offset-2 active:outlin-2 active:outline-indigo-600 active:outline-offset-2"
              >
                Create Workflow
                <%= if @isButtonDisabled do %>
                  <span class="invisible group-hover:visible w-36 py-1 px-3 bg-[#030712] absolute  rounded-md -translate-y-16 -translate-x-32">
                    A workflow name is required
                  </span>
                <% end %>
              </button>
            </span>
          </div>
        </.modal_footer>
      </.form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    changeset = validate_workflow_name(@form_fields)

    socket =
      socket
      |> assign(:form, to_form(changeset, as: :input_form))
      |> assign(:project_id, assigns.id)
      |> assign(:isButtonDisabled, not changeset.valid?)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"workflow_name" => workflow_name}, socket) do
    changeset = validate_workflow(workflow_name, socket)
    socket =
      socket
      |> assign(:isButtonDisabled, not changeset.valid?)
    

    {:noreply, assign(socket, form: to_form(changeset, as: :input_form))}
  end

  @impl true
  def handle_event(
        "create_work_flow",
        %{"workflow_name" => workflow_name},
        socket
      ) do
    changeset = validate_workflow(workflow_name, socket)

    if changeset.valid? do
      navigate_to_new_workflow(socket, workflow_name)
    else
      {:noreply, update_form(socket, changeset)}
    end
  end

  defp validate_workflow(workflow_name, socket) do
    validate_workflow_name(@form_fields, %{
      name: workflow_name,
      project_id: socket.assigns.project_id
    })
    |> Map.put(:action, :validate)
  end

  defp navigate_to_new_workflow(socket, workflow_name) do
    {:noreply,
     push_navigate(socket,
       to:
         ~p"/projects/#{socket.assigns.project_id}/w/new?#{%{name: workflow_name}}"
     )}
  end

  defp update_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :input_form))
  end

  defp changeset(workflow, attrs) do
    {workflow, @types}
    |> cast(attrs, Map.keys(@types))
    |> validate_required([:name])
    |> validate_unique_name?()
  end

  defp validate_unique_name?(changeset) do
    workflow_name = get_field(changeset, :name)
    project_id = get_field(changeset, :project_id)

    if workflow_name && project_id do
      case Workflows.workflow_exists?(project_id, workflow_name) do
        true ->
          add_error(changeset, :name, "Workflow name already been used")

        false ->
          changeset
      end
    else
      changeset
    end
  end

  defp validate_workflow_name(workflow, attrs \\ %{}) do
    changeset(workflow, attrs)
  end
end
