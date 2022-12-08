defmodule LightningWeb.WorkflowLive.WorkflowNameEditor do
  @moduledoc false
  use LightningWeb, :live_component

  alias Lightning.Workflows
  alias LightningWeb.Components.Form

  @impl true
  def update(
        %{workflow: workflow, return_to: return_to, project: project},
        socket
      ) do
    changeset =
      Workflows.change_workflow(workflow, %{name: workflow.name || "Untitled"})

    {:ok,
     socket
     |> assign(
       workflow: workflow,
       changeset: changeset,
       return_to: return_to,
       project: project
     )}
  end

  @impl true
  def handle_event("validate", %{"workflow" => workflow_params}, socket) do
    changeset =
      socket.assigns.workflow
      |> Workflows.change_workflow(workflow_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"workflow" => workflow_params}, socket) do
    case Workflows.update_workflow(socket.assigns.workflow, workflow_params) do
      {:ok, _workflow} ->
        LightningWeb.Endpoint.broadcast!(
          "project_space:#{socket.assigns.project.id}",
          "update",
          %{workflow_id: socket.assigns.workflow.id}
        )

        {:noreply,
         socket
         |> put_flash(:info, "workflow updated successfully")
         |> push_patch(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"workflow-#{@workflow.id}"} class="inline-flex items-center px-2 group">
      <span>/</span>
      <.form
        :let={f}
        for={@changeset}
        id="workflow-inplace-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="flex items-center gap-2"
      >
        <div class="">
          <%= text_input(
            f,
            :name,
            class:
              "border-transparent shadow-sm border-secondary-300 rounded-md group-focus-within:border-secondary-300 sm:text-3xl font-bold text-secondary-900 hover:bg-gray-100"
          ) %>
        </div>
        <div class="hidden group-focus-within:inline">
          <Form.submit_button phx-disable-with="Saving" disabled={!@changeset.valid?}>
            Save
          </Form.submit_button>
        </div>
      </.form>
    </div>
    """
  end
end
