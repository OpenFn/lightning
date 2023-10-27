defmodule LightningWeb.WorkflowLive.Form do
  use LightningWeb, :live_component
  alias Lightning.Workflows
  alias Lightning.Workflows.Workflow
  import Ecto.Changeset
  import WorkflowLive.Modal
  alias WorkflowLive.WorkFlowNameValidator

  # alias Project Struct

  def update(assigns, socket) do
    changeset = WorkFlowNameValidator.validate_workflow(%WorkFlowNameValidator{})

    {
      :ok,
      socket
      |> assign(:form, to_form(changeset))
      |> assign(:project, assigns.id)
    }
  end

  def handle_event("validate", %{"workflow" => workflow_name} = params, socket) do
    changeset =
      WorkFlowNameValidator.validate_workflow(%WorkFlowNameValidator{}, %{
        name: workflow_name,
        project_id: socket.assigns.project
      })
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(%Ecto.Changeset{} = changeset))}
  end

  def handle_event(
        "create_work_flow",
        %{"workflow" => workflow_name} = params,
        socket
      ) do
    changeset =
      WorkFlowNameValidator.validate_workflow(%WorkFlowNameValidator{}, %{
        name: workflow_name,
        project_id: socket.assigns.project
      })

    IO.inspect(changeset, label: "Data")

    if changeset.valid? do
      changeset =
        WorkFlowNameValidator.validate_workflow(%WorkFlowNameValidator{})

      {:noreply, socket |> assign(:form, to_form(changeset))}
    else
      changeset =
        changeset
        |> Map.put(:action, :validate)

      {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
end
