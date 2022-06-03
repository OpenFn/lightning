defmodule LightningWeb.WorkflowDiagramLive do
  @moduledoc """
  Workflow Diagram Component

  The template uses the `WorkflowDiagram` hook, which loads the
  `@openfn/workflow-diagram` React component; and then triggers the
  `component.mounted` event.
  """
  use LightningWeb, :live_component

  alias Lightning.Jobs

  def handle_event("component.mounted", _params, socket) do
    project_space =
      Jobs.get_workflows_for(socket.assigns.project)
      |> to_project_space()

    {:noreply, push_event(socket, "update_project_space", project_space)}
  end

  defp to_project_space(workflows) do
    %{
      "jobs" =>
        workflows
        |> Enum.map(fn {_workflow_id, job} ->
          %{
            "id" => job.id,
            "name" => job.name,
            "adaptor" => job.adaptor,
            "trigger" => %{
              "type" => job.trigger.type,
              "upstreamJob" => job.trigger.upstream_job_id
            }
          }
        end)
    }
  end
end
