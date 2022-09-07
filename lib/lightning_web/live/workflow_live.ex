defmodule LightningWeb.WorkflowLive do
  @moduledoc false
  use LightningWeb, :live_view

  on_mount {LightningWeb.Hooks, :project_scope}

  alias Lightning.Workflows

  defp encode_project_space(project) do
    Workflows.get_workflows_for(project)
    |> Workflows.to_project_space()
    |> Jason.encode!()
    |> Base.encode64()
  end

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.project
    LightningWeb.Endpoint.subscribe("project_space:#{project.id}")

    {:ok,
     socket
     |> assign(
       active_menu_item: :projects,
       encoded_project_space: encode_project_space(project)
     )}
  end

  @doc """
  Update the encoded project space, when a change is broadcasted via pubsub
  """
  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "update", payload: _payload},
        socket
      ) do
    {:noreply,
     socket
     |> assign(
       encoded_project_space: encode_project_space(socket.assigns.project)
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     apply_action(
       socket,
       socket.assigns.live_action,
       params
     )}
  end

  defp apply_action(socket, :show, _params) do
    socket
    |> assign(
      active_menu_item: :overview,
      page_title: socket.assigns.project.name
    )
  end

  defp apply_action(socket, :edit_job, %{"job_id" => job_id}) do
    job = Lightning.Jobs.get_job!(job_id)

    socket
    |> assign(
      active_menu_item: :overview,
      job: job,
      page_title: socket.assigns.project.name
    )
  end

  defp apply_action(socket, :edit_workflow, %{"workflow_id" => workflow_id}) do
    workflow = Lightning.Workflows.get_workflow!(workflow_id)

    socket
    |> assign(page_title: socket.assigns.project.name, workflow: workflow)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layout.page_content>
      <:header>
        <Layout.header title={@page_title} socket={@socket}>
          <%= live_redirect to: Routes.project_job_index_path(@socket, :index, @project.id) do %>
            <div class="inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-secondary-200 hover:bg-secondary-300 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-secondary-500">
              <div class="h-full">
                <Heroicons.Solid.table class="h-4 w-4 inline-block" />
              </div>
            </div>
          <% end %>
          &nbsp;&nbsp;
          <%= live_redirect to: Routes.project_job_edit_path(@socket, :new, @project.id) do %>
            <Common.button>
              <div class="h-full">
                <Heroicons.Outline.plus class="h-4 w-4 inline-block" />
                <span class="inline-block align-middle">New Job</span>
              </div>
            </Common.button>
          <% end %>
        </Layout.header>
      </:header>
      <div class="relative h-full">
        <%= case @live_action do %>
          <% :edit_job -> %>
            <div class="absolute top-0 right-0 m-2 z-10">
              <div class="w-80 bg-white rounded-md shadow-xl ring-1 ring-black ring-opacity-5 p-3">
                <.live_component
                  module={LightningWeb.JobLive.InspectorFormComponent}
                  id={@job.id}
                  job={@job}
                  action={:edit}
                  project={@project}
                  return_to={
                    Routes.project_workflow_path(
                      @socket,
                      :show,
                      @project.id
                    )
                  }
                />
              </div>
            </div>
          <% :edit_workflow -> %>
            <div class="absolute top-0 right-0 m-2 z-10">
              <div class="w-80 bg-white rounded-md shadow-xl ring-1 ring-black ring-opacity-5 p-3">
                <.live_component
                  module={LightningWeb.WorkflowLive.WorkflowInspector}
                  id={@workflow.id}
                  workflow={@workflow}
                  project={@project}
                  return_to={
                    Routes.project_workflow_path(
                      @socket,
                      :show,
                      @project.id
                    )
                  }
                />
              </div>
            </div>
          <% _ -> %>
        <% end %>
        <div
          phx-hook="WorkflowDiagram"
          class="h-full w-full"
          id={"hook-#{@project.id}"}
          phx-update="ignore"
          base-path={Routes.project_workflow_path(@socket, :show, @project.id)}
          data-project-space={@encoded_project_space}
        >
        </div>
      </div>
    </Layout.page_content>
    """
  end
end
