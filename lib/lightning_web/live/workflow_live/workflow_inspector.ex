defmodule LightningWeb.WorkflowLive.WorkflowInspector do
  @moduledoc false
  use LightningWeb, :live_component

  alias Lightning.Workflows
  alias LightningWeb.Components.Form

  @impl true
  def update(
        %{workflow: workflow, return_to: return_to, project: project},
        socket
      ) do
    changeset = Workflows.change_workflow(workflow, %{})

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
          %{}
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
    <div id={"workflow-#{@workflow.id}"}>
      <.form
        :let={f}
        for={@changeset}
        id="workflow-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="md:grid md:grid-cols-2 md:gap-4">
          <div class="md:col-span-2">
            <Form.text_field form={f} id={:name} />
          </div>
        </div>
        <Form.divider />
        <div class="md:grid md:grid-cols-2 md:gap-4">
          <div class="md:col-span-2 w-full">
            <span>
              <%= live_patch("Cancel",
                class:
                  "inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-secondary-700 hover:bg-secondary-800 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-secondary-500",
                to: @return_to
              ) %>
            </span>
            <Form.submit_button phx-disable-with="Saving" changeset={@changeset}>
              Save
            </Form.submit_button>
          </div>
        </div>
      </.form>
    </div>
    """
  end
end
