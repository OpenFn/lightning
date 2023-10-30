defmodule LightningWeb.WorkflowLive.Form do
  use LightningWeb, :live_component
  import WorkflowLive.Modal
  alias WorkflowLive.WorkFlowNameValidator

  @impl true
  def update(assigns, socket) do
    changeset = WorkFlowNameValidator.validate_workflow(%WorkFlowNameValidator{})

    socket =
      socket
      |> assign(:form, to_form(changeset))
      |> assign(:project_id, assigns.id)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"workflow" => workflow_name}, socket) do
    changeset = validate_workflow(workflow_name, socket)
    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("create_work_flow", %{"workflow" => workflow_name}, socket) do
    changeset = validate_workflow(workflow_name, socket)

    if changeset.valid? do
      navigate_to_new_workflow(socket, workflow_name)
    else
      {:noreply, update_form(socket, changeset)}
    end
  end

  defp validate_workflow(workflow_name, socket) do
    WorkFlowNameValidator.validate_workflow(%WorkFlowNameValidator{}, %{
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
    assign(socket, :form, to_form(changeset))
  end
end
