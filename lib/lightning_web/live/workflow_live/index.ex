defmodule LightningWeb.WorkflowLive.Index do
  @moduledoc false
  use LightningWeb, :live_view

  on_mount {LightningWeb.Hooks, :project_scope}

  alias Lightning.Workflows
  alias Lightning.Policies.{Permissions, ProjectUsers}
  import LightningWeb.WorkflowLive.Components
  attr :can_create_workflow, :boolean
  attr :can_delete_workflow, :boolean
  attr :workflows, :list
  attr :project, Lightning.Projects.Project

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:title><%= @page_title %></:title>
        </LayoutComponents.header>
      </:header>
      <div class="relative h-full flex">
        <LayoutComponents.centered>
          <.workflow_list
            can_create_workflow={@can_create_workflow}
            can_delete_workflow={@can_delete_workflow}
            workflows={@workflows}
            project={@project}
          />

          <.create_workflow_modal>
            <.live_component
              module={LightningWeb.WorkflowLive.Form}
              id={@project.id}
              }
            />
          </.create_workflow_modal>
        </LayoutComponents.centered>
      </div>
    </LayoutComponents.page_content>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    can_create_workflow =
      ProjectUsers
      |> Permissions.can?(
        :create_workflow,
        socket.assigns.current_user,
        socket.assigns.project
      )

    can_delete_workflow =
      ProjectUsers
      |> Permissions.can?(
        :delete_workflow,
        socket.assigns.current_user,
        socket.assigns.project
      )

    {:ok,
     socket
     |> assign(
       can_delete_workflow: can_delete_workflow,
       can_create_workflow: can_create_workflow
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _) do
    socket
    |> assign(
      active_menu_item: :overview,
      page_title: "Workflows",
      workflows: Workflows.get_workflows_for(socket.assigns.project)
    )
  end

  @impl true
  def handle_event("delete_workflow", %{"id" => id}, socket) do
    if socket.assigns.can_delete_workflow do
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
            |> put_flash(:info, "Workflow successfully deleted.")
          }

        {:error, _changeset} ->
          {:noreply, socket |> put_flash(:error, "Can't delete workflow")}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action.")}
    end
  end
end
