defmodule LightningWeb.WorkflowNewLive do
  @moduledoc false
  use LightningWeb, :live_view

  alias Lightning.Workflows.Workflow
  alias LightningWeb.Components.Form
  alias LightningWeb.WorkflowNewLive.WorkflowParams

  on_mount {LightningWeb.Hooks, :project_scope}

  attr :changeset, :map, required: true

  def workflow_name_field(assigns) do
    ~H"""
    <.form :let={f} for={@changeset}>
      <div class="relative">
        <%= text_input(
          f,
          :name,
          class: "peer block w-full
            text-2xl font-bold text-secondary-900
            border-0 py-1.5 focus:ring-0",
          placeholder: "Untitled"
        ) %>
        <div
          class="absolute inset-x-0 bottom-0
                 peer-hover:border-t peer-hover:border-gray-300
                 peer-focus:border-t-2 peer-focus:border-indigo-600"
          aria-hidden="true"
        >
        </div>
      </div>
    </.form>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header socket={@socket}>
          <:title>
            <.workflow_name_field changeset={@changeset} />
          </:title>
          <Form.submit_button
            class=""
            phx-disable-with="Saving..."
            disabled={!@changeset.valid?}
          >
            Save
          </Form.submit_button>
        </LayoutComponents.header>
      </:header>
      <div class="relative h-full flex">
        <div phx-hook="WorkflowEditor" id={@project.id} phx-update="ignore">
          <!-- Before Editor component has mounted -->
          Loading...
        </div>
      </div>
    </LayoutComponents.page_content>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.project

    {:ok,
     socket
     |> assign(
       project: project,
       page_title: "",
       active_menu_item: :projects
     )}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    workflow = %Workflow{}
    job_1_id = Ecto.UUID.generate()
    job_2_id = Ecto.UUID.generate()
    trigger_1_id = Ecto.UUID.generate()

    params = %{
      "name" => nil,
      "project_id" => socket.assigns.project.id,
      "jobs" => [
        %{"id" => job_1_id, "name" => ""},
        %{"id" => job_2_id, "name" => "job-2"}
      ],
      "triggers" => [
        %{"id" => trigger_1_id, "type" => "webhook"}
      ],
      "edges" => [
        %{
          "id" => Ecto.UUID.generate(),
          "source_trigger_id" => trigger_1_id,
          "condition" => "true",
          "target_job_id" => job_1_id
        },
        %{
          "id" => Ecto.UUID.generate(),
          "source_job_id" => job_1_id,
          "condition" => ":on_success",
          "target_job_id" => job_2_id
        }
      ]
    }

    changeset = workflow |> Workflow.changeset(params)
    workflow_params = changeset |> WorkflowParams.to_map()

    {:noreply,
     assign(socket,
       page_title: "New Workflow",
       workflow: workflow,
       changeset: changeset,
       workflow_params: workflow_params
     )}
  end

  @impl true
  def handle_event("get-initial-state", _params, socket) do
    {:reply, socket.assigns.workflow_params, socket}
  end

  def handle_event("push-change", %{"patches" => patches}, socket) do
    # Apply the incoming patches to the current workflow params producing a new
    # set of params.
    {:ok, params} =
      WorkflowParams.apply_patches(socket.assigns.workflow_params, patches)

    # Build a new changeset from the new params
    changeset = socket.assigns.workflow |> Workflow.changeset(params)

    # Prepare a new set of workflow params from the changeset
    workflow_params = changeset |> WorkflowParams.to_map()

    # Calculate the difference between the new params and changes introduced by
    # the changeset/validation.
    patches = WorkflowParams.to_patches(params, workflow_params)

    {:reply, %{patches: patches},
     socket |> assign(workflow_params: workflow_params, changeset: changeset)}
  end
end
