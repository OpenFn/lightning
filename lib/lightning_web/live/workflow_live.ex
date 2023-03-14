defmodule LightningWeb.WorkflowLive do
  @moduledoc false
  use LightningWeb, :live_view

  on_mount {LightningWeb.Hooks, :project_scope}

  alias Lightning.Jobs
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Workflows
  import LightningWeb.WorkflowLive.Components

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header socket={@socket}>
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
                      ~p"/projects/#{@project.id}/w/#{@current_workflow.id}"
                    }
                  />
                </div>
            <% end %>
          </:title>
        </LayoutComponents.header>
      </:header>
      <div class="relative h-full flex">
        <%= case @live_action do %>
          <% :index -> %>
            <LayoutComponents.centered>
              <.workflow_list
                can_create_workflow={@can_create_workflow}
                workflows={@workflows}
                project={@project}
              />
            </LayoutComponents.centered>
          <% :new_job -> %>
            <div class="grow">
              <.workflow_diagram
                base_path={~p"/projects/#{@project.id}/w/#{@current_workflow.id}"}
                id={@current_workflow.id}
                selected_node={@selected_node_id}
                encoded_project_space={@encoded_project_space}
              />
            </div>
            <div class="grow-0 w-1/2 relative">
              <div class="absolute w-full inset-y-0 z-10">
                <div class="w-auto h-full" id="job-pane">
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
                      ~p"/projects/#{@project.id}/w/#{@current_workflow.id}"
                    }
                    can_delete_job={@can_delete_job}
                    can_edit_job={@can_edit_job}
                  />
                </div>
              </div>
            </div>
          <% :edit_job -> %>
            <div class="grow">
              <.workflow_diagram
                base_path={~p"/projects/#{@project.id}/w/#{@current_workflow.id}"}
                id={@current_workflow.id}
                selected_node={@job.id}
                encoded_project_space={@encoded_project_space}
              />
            </div>
            <div class="grow-0 w-1/2 relative">
              <div class="absolute w-full inset-y-0 z-10">
                <div class="w-auto h-full" id={"job-pane-#{@job.id}"}>
                  <.live_component
                    module={LightningWeb.JobLive.JobBuilder}
                    id={"builder-#{@job.id}"}
                    job={@job}
                    project={@project}
                    current_user={@current_user}
                    builder_state={@builder_state}
                    return_to={
                      ~p"/projects/#{@project.id}/w/#{@current_workflow.id}"
                    }
                    can_delete_job={@can_delete_job}
                    can_edit_job={@can_edit_job}
                  />
                </div>
              </div>
            </div>
          <% :show -> %>
            <div class="grow">
              <%= if Enum.any?(@current_workflow.jobs) do %>
                <.workflow_diagram
                  base_path={~p"/projects/#{@project.id}/w/#{@current_workflow.id}"}
                  id={@current_workflow.id}
                  encoded_project_space={@encoded_project_space}
                />
              <% else %>
                <.create_job_panel
                  socket={@socket}
                  project={@project}
                  workflow={@current_workflow}
                  can_create_job={@can_create_job}
                />
              <% end %>
            </div>
          <% :edit_workflow -> %>
            <div class="absolute top-0 right-0 m-2 z-10">
              <div class="w-80 bg-white rounded-md shadow-xl ring-1 ring-black ring-opacity-5 p-3">
                <.live_component
                  module={LightningWeb.WorkflowLive.WorkflowInspector}
                  id={@current_workflow.id}
                  workflow={@current_workflow}
                  project={@project}
                  return_to={~p"/projects/#{@project.id}/w/#{@current_workflow.id}"}
                />
              </div>
            </div>
          <% _ -> %>
        <% end %>
      </div>
    </LayoutComponents.page_content>
    """
  end

  def encode_project_space(%Workflows.Workflow{} = workflow) do
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

    can_create_workflow =
      ProjectUsers
      |> Permissions.can(
        :create_workflow,
        socket.assigns.current_user,
        socket.assigns.project
      )

    can_create_job =
      ProjectUsers
      |> Permissions.can(
        :create_job,
        socket.assigns.current_user,
        socket.assigns.project
      )

    can_edit_job =
      ProjectUsers
      |> Permissions.can(
        :edit_job,
        socket.assigns.current_user,
        socket.assigns.project
      )

    can_delete_job =
      ProjectUsers
      |> Permissions.can(
        :delete_job,
        socket.assigns.current_user,
        socket.assigns.project
      )

    {:ok,
     socket
     |> assign(
       can_create_workflow: can_create_workflow,
       can_create_job: can_create_job,
       can_edit_job: can_edit_job,
       can_delete_job: can_delete_job,
       active_menu_item: :projects,
       new_credential: false,
       builder_state: %{}
     )}
  end

  defp create_workflow(%{assigns: %{can_create_workflow: false}} = socket) do
    {:noreply,
     socket
     |> put_flash(:error, "You are not authorized to perform this action.")
     |> push_patch(to: ~p"/projects/#{socket.assigns.project.id}/w")}
  end

  defp create_workflow(%{assigns: %{can_create_workflow: true}} = socket) do
    {:ok, %Workflows.Workflow{id: workflow_id}} =
      Workflows.create_workflow(%{project_id: socket.assigns.project.id})

    {:noreply,
     socket
     |> assign(workflows: Workflows.get_workflows_for(socket.assigns.project))
     |> push_patch(
       to: ~p"/projects/#{socket.assigns.project.id}/w/#{workflow_id}"
     )}
  end

  @impl true
  def handle_event("delete_job", %{"id" => id}, socket) do
    if socket.assigns.can_edit_job do
      job = Jobs.get_job!(id)

      case Jobs.delete_job(job) do
        {:ok, _} ->
          LightningWeb.Endpoint.broadcast!(
            "project_space:#{socket.assigns.project.id}",
            "update",
            %{workflow_id: job.workflow_id}
          )

          {:noreply,
           socket
           |> put_flash(:info, "Job deleted successfully")
           |> push_patch(
             to:
               ~p"/projects/#{socket.assigns.project.id}/w/#{socket.assigns.current_workflow.id}"
           )}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(
             :error,
             "Unable to delete this job because it has downstream jobs"
           )}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action.")
       |> push_patch(
         to:
           ~p"/projects/#{socket.assigns.project.id}/w/#{socket.assigns.current_workflow.id}"
       )}
    end
  end

  @impl true
  def handle_event("copied_to_clipboard", _, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Copied webhook URL to clipboard")}
  end

  @impl true
  def handle_event("create_job", _, socket) do
    if socket.assigns.can_create_job do
      {:noreply,
       socket
       |> push_patch(
         to:
           ~p"/projects/#{socket.assigns.project.id}/w/#{socket.assigns.current_workflow.id}/j/new"
       )}
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action.")}
    end
  end

  @impl true
  def handle_event("create_workflow", _, socket) do
    create_workflow(socket)
  end

  @impl true
  def handle_event("delete_workflow", %{"id" => id}, socket) do
    Workflows.get_workflow!(id)
    |> Workflows.mark_for_deletion()
    |> case do
      {:ok, _} ->
        {
          :noreply,
          socket
          |> assign(
            workflows: Workflows.get_workflows_for(socket.assigns.project)
          )
          |> put_flash(:info, "Workflow deleted successfully")
        }

      {:error, _changeset} ->
        {:noreply, socket |> put_flash(:error, "Can't delete workflow")}
    end
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

  # A generic handler for forwarding updates from PubSub
  @impl true
  def handle_info({:forward, mod, opts}, socket) do
    send_update(mod, opts)
    {:noreply, socket}
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
      selected_node_id: upstream_job.id,
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
      selected_node_id: nil,
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

    socket
    |> assign(
      page_title: "Workflows",
      current_workflow: workflow,
      encoded_project_space: encode_project_space(workflow)
    )
  end
end
