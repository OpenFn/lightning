defmodule LightningWeb.WorkflowLive.Index do
  @moduledoc false
  use LightningWeb, :live_view

  on_mount {LightningWeb.Hooks, :project_scope}

  alias Lightning.Workflows
  alias Lightning.Policies.{Permissions, ProjectUsers}
  alias LightningWeb.WorkflowLive.NewWorkflowForm
  alias Lightning.DashboardMetrics

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
          <.workflow_metrics metrics={@metrics} />
          <.workflow_list
            can_create_workflow={@can_create_workflow}
            can_delete_workflow={@can_delete_workflow}
            workflows={@workflows}
            project={@project}
          />
          <.create_workflow_modal form={@form} />
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
     )
     |> assign_workflow_form(
       NewWorkflowForm.validate(%{}, socket.assigns.project.id)
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
      page_title: "Dashboard",
      metrics: DashboardMetrics.get_metrics(socket.assigns.project.id),
      workflows: Workflows.get_workflows_for(socket.assigns.project)
    )
  end

  @impl true
  def handle_event("validate_workflow", %{"new_workflow" => params}, socket) do
    changeset =
      NewWorkflowForm.validate(params, socket.assigns.project.id)
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign_workflow_form(changeset)}
  end

  def handle_event("create_work_flow", %{"new_workflow" => params}, socket) do
    changeset =
      params
      |> NewWorkflowForm.validate(socket.assigns.project.id)
      |> NewWorkflowForm.validate_for_save()

    if changeset.valid? do
      {:noreply,
       push_navigate(socket,
         to:
           ~p"/projects/#{socket.assigns.project}/w/new?#{%{name: Ecto.Changeset.get_field(changeset, :name)}}"
       )}
    else
      {:noreply, socket |> assign_workflow_form(changeset)}
    end
  end

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

  defp assign_workflow_form(socket, changeset) do
    socket |> assign(form: to_form(changeset, as: :new_workflow))
  end
end
