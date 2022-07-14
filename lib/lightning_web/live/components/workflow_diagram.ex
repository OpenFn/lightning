defmodule LightningWeb.Components.WorkflowDiagram do
  @moduledoc """
  Workflow Diagram Component

  The template uses the `WorkflowDiagram` hook, which loads the
  `@openfn/workflow-diagram` React component; and then triggers the
  `component_mounted` event.
  """
  use LightningWeb, :live_component

  alias Lightning.Jobs

  def mount(socket) do
    {:ok, socket}
  end

  def update(assigns, socket) do
    selected_job =
      if id = assigns.selected_id do
        Jobs.get_job!(id)
      else
        nil
      end

    {:ok, socket |> assign(assigns) |> assign(selected_job: selected_job)}
  end

  def handle_event("component_mounted", _params, socket) do
    project_space =
      Jobs.get_workflows_for(socket.assigns.project)
      |> to_project_space()

    {:noreply, push_event(socket, "update_project_space", project_space)}
  end

  def render(assigns) do
    ~H"""
    <div class="relative h-full">
      <%= if @selected_job do %>
        <div class="absolute top-0 right-0 m-2 z-10 mt-[5%] mr-4">
          <div class="w-80 bg-white rounded-md shadow-xl ring-1 ring-black ring-opacity-5  p-3">
            <.live_component
              module={LightningWeb.JobLive.InspectorFormComponent}
              id={@selected_job.id}
              action={:edit}
              job={@selected_job}
              project={@project}
              return_to={
                Routes.project_dashboard_index_path(@socket, :show, @project.id)
              }
            />
          </div>
        </div>
      <% end %>
      <div
        phx-hook="WorkflowDiagram"
        class="h-full w-full"
        id={"hook-#{@project.id}"}
        phx-update="ignore"
        phx-target={@myself}
      >
      </div>
    </div>
    """
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
