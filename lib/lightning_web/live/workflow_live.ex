defmodule LightningWeb.WorkflowLive do
  @moduledoc false
  use LightningWeb, :live_view

  on_mount {LightningWeb.Hooks, :project_scope}

  alias Lightning.Workflows
  import LightningWeb.WorkflowLive.Components

  @impl true
  def render(assigns) do
    assigns = assigns |> assign_new(:show_canvas, fn -> true end)

    ~H"""
    <Layout.page_content>
      <:header>
        <Layout.header socket={@socket}>
          <:title>
            <%= @page_title %>
            <%= case @live_action do %>
              <% :index -> %>
              <% :new_job -> %>
                <div>&nbsp;/&nbsp;<%= @current_workflow.name %></div>
              <% _ -> %>
                <div>
                  <.live_component
                    module={LightningWeb.WorkflowLive.WorkflowNameEditor}
                    id={@current_workflow.id}
                    workflow={@current_workflow}
                    project={@project}
                    return_to={
                      Routes.project_workflow_path(
                        @socket,
                        :show,
                        @project.id,
                        @current_workflow.id
                      )
                    }
                  />
                </div>
            <% end %>
          </:title>
          <.link navigate={
            Routes.project_job_index_path(@socket, :index, @project.id)
          }>
            <div class="inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-secondary-200 hover:bg-secondary-300 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-secondary-500">
              <div class="h-full">
                <Heroicons.table_cells solid class="h-4 w-4 inline-block" />
              </div>
            </div>
          </.link>
        </Layout.header>
      </:header>
      <div class="relative h-full">
        <%= case @live_action do %>
          <% :index -> %>
            <Layout.centered>
              <.workflow_list workflows={@workflows} project={@project} />
            </Layout.centered>
          <% :new_job -> %>
            <div class="absolute w-1/3 inset-y-0 right-0 bottom-0 z-10">
              <div
                class="w-auto h-full bg-white shadow-xl ring-1 ring-black ring-opacity-5"
                id="job-pane"
              >
                <.live_component
                  module={LightningWeb.JobLive.JobBuilder}
                  id="builder-new"
                  job={@job}
                  workflow={assigns[:workflow]}
                  params={@job_params}
                  project={@project}
                  current_user={@current_user}
                  builder_state={@builder_state}
                  return_to={
                    Routes.project_workflow_path(
                      @socket,
                      :show,
                      @project.id,
                      @current_workflow.id
                    )
                  }
                />
              </div>
            </div>
          <% :edit_job -> %>
            <div class="absolute w-1/2 inset-y-0 right-0 z-10">
              <div class="w-auto h-full" id={"job-pane-#{@job.id}"}>
                <.live_component
                  module={LightningWeb.JobLive.JobBuilder}
                  id={"builder-#{@job.id}"}
                  job={@job}
                  project={@project}
                  current_user={@current_user}
                  builder_state={@builder_state}
                  return_to={
                    Routes.project_workflow_path(
                      @socket,
                      :show,
                      @project.id,
                      @current_workflow.id
                    )
                  }
                />
              </div>
            </div>
          <% :show -> %>
            <%= if length(@current_workflow.jobs) == 0 do %>
              <div class="w-1/2 h-16 text-center my-16 mx-auto pt-4">
                <div class="text-sm font-semibold text-gray-500 pb-4">
                  Create your first job to get started.
                </div>
                <div class="text-xs text-gray-400">
                  <.link patch={
                    Routes.project_workflow_path(
                      @socket,
                      :new_job,
                      @project.id,
                      @current_workflow.id
                    )
                  }>
                    <Common.button>
                      <div class="h-full">
                        <Heroicons.plus class="h-4 w-4 inline-block" />
                        <span class="inline-block align-middle">
                          Create job
                        </span>
                      </div>
                    </Common.button>
                  </.link>
                </div>
              </div>
            <% end %>
          <% :edit_workflow -> %>
            <div class="absolute top-0 right-0 m-2 z-10">
              <div class="w-80 bg-white rounded-md shadow-xl ring-1 ring-black ring-opacity-5 p-3">
                <.live_component
                  module={LightningWeb.WorkflowLive.WorkflowInspector}
                  id={@current_workflow.id}
                  workflow={@current_workflow}
                  project={@project}
                  return_to={
                    Routes.project_workflow_path(
                      @socket,
                      :show,
                      @project.id,
                      @current_workflow.id
                    )
                  }
                />
              </div>
            </div>
          <% _ -> %>
        <% end %>
        <%= if @show_canvas do %>
          <div
            phx-hook="WorkflowDiagram"
            class="h-full w-full"
            id={"hook-#{@project.id}"}
            phx-update="ignore"
            base-path={
              Routes.project_workflow_path(
                @socket,
                :show,
                @project.id,
                @current_workflow.id
              )
            }
            data-project-space={@encoded_project_space}
          >
          </div>
        <% end %>
      </div>
    </Layout.page_content>
    """
  end

  defp encode_project_space(%Workflows.Workflow{} = workflow) do
    workflow
    |> Lightning.Repo.preload(
      jobs: [:credential, :workflow, trigger: [:upstream_job]]
    )
    |> List.wrap()
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
       new_credential: false,
       builder_state: %{}
     )}
  end

  @impl true
  def handle_event("copied-to-clipboard", _, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Copied webhook URL to clipboard")}
  end

  @impl true
  def handle_event("create-workflow", _, socket) do
    {:ok, %Workflows.Workflow{id: workflow_id}} =
      Workflows.create_workflow(%{project_id: socket.assigns.project.id})

    {:noreply,
     socket
     |> assign(workflows: Workflows.get_workflows_for(socket.assigns.project))
     |> push_patch(
       to:
         Routes.project_workflow_path(
           socket,
           :show,
           socket.assigns.project.id,
           workflow_id
         )
     )}
  end

  @doc """
  Update the encoded project space, when a change is broadcasted via pubsub
  """
  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{
          event: "update",
          payload: %{workflow_id: workflow_id}
        },
        socket
      ) do
    workflow = Lightning.Workflows.get_workflow!(workflow_id)

    {:noreply,
     socket
     |> assign(encoded_project_space: encode_project_space(workflow))}
  end

  # Update the builder state when an input dataclip is selected for a specific job
  def handle_info(
        {:update_builder_state, %{dataclip: dataclip, job_id: job_id}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(
       builder_state:
         socket.assigns.builder_state
         |> Map.merge(%{dataclip: dataclip, job_id: job_id})
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(
      active_menu_item: :overview,
      page_title: "Workflows",
      show_canvas: false,
      workflows: Workflows.get_workflows_for(socket.assigns.project)
    )
  end

  defp apply_action(socket, :new_job, %{"upstream_id" => upstream_id}) do
    upstream_job = Lightning.Jobs.get_job!(upstream_id)

    %Lightning.Jobs.Job{workflow: workflow} =
      upstream_job |> Lightning.Repo.preload(:workflow)

    socket
    |> assign(
      active_menu_item: :overview,
      job: %Lightning.Jobs.Job{},
      job_params: %{
        "workflow_id" => upstream_job.workflow_id,
        "trigger" => %{
          "type" => :on_job_success,
          "upstream_job_id" => upstream_job.id
        }
      },
      current_workflow: workflow,
      encoded_project_space: encode_project_space(workflow),
      page_title: "Workflows"
    )
  end

  defp apply_action(socket, :new_job, %{
         "project_id" => project_id,
         "workflow_id" => workflow_id
       }) do
    workflow = Lightning.Workflows.get_workflow!(workflow_id)

    socket
    |> assign(
      active_menu_item: :overview,
      job: %Lightning.Jobs.Job{},
      job_params: %{
        "trigger" => %{"type" => :webhook}
      },
      current_workflow: workflow,
      workflow:
        Workflows.Workflow.changeset(workflow, %{
          name: workflow.name,
          project_id: project_id
        }),
      encoded_project_space: encode_project_space(workflow),
      page_title: "Workflows"
    )
  end

  defp apply_action(socket, :edit_job, %{"job_id" => job_id}) do
    job = Lightning.Jobs.get_job!(job_id)

    %Lightning.Jobs.Job{workflow: workflow} =
      job |> Lightning.Repo.preload(:workflow)

    socket
    |> assign(
      active_menu_item: :overview,
      job: job,
      current_workflow: workflow,
      encoded_project_space: encode_project_space(workflow),
      page_title: "Workflows"
    )
  end

  defp apply_action(socket, :edit_workflow, %{
         "project_id" => project_id,
         "workflow_id" => workflow_id
       }) do
    workflow = Lightning.Workflows.get_workflow!(workflow_id)

    socket
    |> assign(
      page_title: "Workflows",
      current_workflow: workflow,
      encoded_project_space: encode_project_space(workflow),
      workflow:
        Workflows.Workflow.changeset(workflow, %{
          name: workflow.name,
          project_id: project_id
        })
    )
  end

  defp apply_action(socket, :show, %{"workflow_id" => workflow_id}) do
    workflow =
      Lightning.Workflows.get_workflow!(workflow_id)
      |> Lightning.Repo.preload(
        jobs: [:credential, :workflow, trigger: [:upstream_job]]
      )

    # we display the canvas only if workflow has jobs, otherwise we prompt the user to create a job
    show_canvas = length(workflow.jobs) > 0

    socket
    |> assign(
      page_title: "Workflows",
      current_workflow: workflow,
      show_canvas: show_canvas,
      encoded_project_space: encode_project_space(workflow)
    )
  end
end
