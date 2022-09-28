defmodule LightningWeb.WorkflowLive do
  @moduledoc false
  use LightningWeb, :live_view

  on_mount {LightningWeb.Hooks, :project_scope}

  alias Lightning.Workflows
  alias Lightning.Projects

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
       encoded_project_space: encode_project_space(project),
       new_credential: false,
       initial_job_params: %{}
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

  def handle_info({:added_credential, credential}, socket) do
    project = socket.assigns.project

    project_credential =
      Projects.get_project_credential(project.id, credential.id)

    {:noreply,
      socket
      |> put_flash(:info, "Credential created successfully")
      |> assign(
       initial_job_params: %{
        "project_credential_id" => project_credential.id,
        "project_credential" => project_credential
       }
      )
      |> assign(:new_credential, false)
    }
  end

  @impl true
  def handle_event("new-credential", _params, socket) do
    {:noreply,
     socket
     |> assign(:new_credential, true)}
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, socket |> assign(:new_credential, false)}
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

  defp apply_action(socket, :new_job, %{"upstream_id" => upstream_id}) do
    upstream_job = Lightning.Jobs.get_job!(upstream_id)

    job = %Lightning.Jobs.Job{
      project_id: socket.assigns.project.id,
      trigger: %Lightning.Jobs.Trigger{
        type: :on_job_success,
        upstream_job_id: upstream_job.id
      }
    }

    socket
    |> assign(
      active_menu_item: :overview,
      job: job,
      initial_job_params: %{
        "project_id" => socket.assigns.project.id
      },
      page_title: socket.assigns.project.name
    )
  end

  defp apply_action(socket, :edit_job, %{"job_id" => job_id}) do
    job = Lightning.Jobs.get_job!(job_id)

    socket
    |> assign(
      active_menu_item: :overview,
      job: job,
      initial_job_params: %{},
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
        <%= if @new_credential do %>
          <.live_component
            module={LightningWeb.CredentialLive.CredentialEditModal}
            id="new-credential"
            job={@job}
            project={@project}
            current_user={@current_user}
          />
        <% end %>
        <%= case @live_action do %>
          <% :new_job -> %>
            <div class="absolute top-0 right-0 m-2 z-10">
              <div class="w-80 bg-white rounded-md shadow-xl ring-1 ring-black ring-opacity-5 p-3">
                <.live_component
                  module={LightningWeb.JobLive.InspectorFormComponent}
                  id="new-job"
                  job={@job}
                  action={:new}
                  project={@project}
                  initial_job_params={@initial_job_params}
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
          <% :edit_job -> %>
            <div class="absolute top-0 right-0 m-2 z-10">
              <div class="w-80 bg-white rounded-md shadow-xl ring-1 ring-black ring-opacity-5 p-3">
                <.live_component
                  module={LightningWeb.JobLive.InspectorFormComponent}
                  id={@job.id}
                  job={@job}
                  action={:edit}
                  project={@project}
                  initial_job_params={@initial_job_params}
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
