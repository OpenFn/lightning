defmodule LightningWeb.WorkflowLive.Index do
  @moduledoc false
  use LightningWeb, :live_view

  import LightningWeb.WorkflowLive.Components

  alias Lightning.DashboardStats
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Workflows
  alias Lightning.Workflows.WorkflowUsageLimiter
  alias LightningWeb.LiveHelpers
  alias LightningWeb.WorkflowLive.DashboardComponents
  alias LightningWeb.WorkflowLive.Helpers
  alias LightningWeb.WorkflowLive.NewWorkflowForm

  # alias Phoenix.LiveView.TagEngine

  on_mount {LightningWeb.Hooks, :project_scope}

  # TODO - make this configurable some day
  @dashboard_period "last 30 days"

  attr :dashboard_period, :string, default: @dashboard_period
  attr :can_create_workflow, :boolean
  attr :can_delete_workflow, :boolean
  attr :workflows, :list
  attr :project, Lightning.Projects.Project
  attr :banner, :map, default: nil

  @impl true
  def render(%{project: %{id: project_id}} = assigns) do
    assigns = check_workflow_and_run_limits(assigns, project_id)

    ~H"""
    <LayoutComponents.page_content>
      <:banner>
        <Common.dynamic_component
          :if={assigns[:banner]}
          function={@banner.function}
          args={@banner.attrs}
        />
      </:banner>
      <:header>
        <LayoutComponents.header current_user={@current_user} project={@project}>
          <:title>{@page_title}</:title>
          <:period>{@dashboard_period}</:period>
        </LayoutComponents.header>
      </:header>
      <LayoutComponents.centered>
        <DashboardComponents.project_metrics metrics={@metrics} project={@project} />
        <DashboardComponents.workflow_list
          period={@dashboard_period}
          can_create_workflow={@can_create_workflow}
          can_delete_workflow={@can_delete_workflow}
          workflow_creation_limit_error={@workflow_creation_limit_error}
          workflows_stats={@workflows_stats}
          project={@project}
        />
        <.create_workflow_modal form={@form} />
      </LayoutComponents.centered>
    </LayoutComponents.page_content>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    %{current_user: current_user, project: project} = socket.assigns

    can_create_workflow =
      ProjectUsers
      |> Permissions.can?(
        :create_workflow,
        current_user,
        project
      )

    can_delete_workflow =
      ProjectUsers
      |> Permissions.can?(
        :delete_workflow,
        current_user,
        project
      )

    {:ok,
     socket
     |> assign(
       can_delete_workflow: can_delete_workflow,
       can_create_workflow: can_create_workflow
     )
     |> assign_workflow_form(NewWorkflowForm.validate(%{}, project.id))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    %{project: project} = socket.assigns

    workflows_stats =
      project
      |> Workflows.get_workflows_for()
      |> Enum.map(&DashboardStats.get_workflow_stats/1)

    socket
    |> assign(
      active_menu_item: :overview,
      page_title: "Workflows",
      metrics: DashboardStats.aggregate_project_metrics(workflows_stats),
      workflows_stats: workflows_stats
    )
  end

  @impl true
  def handle_event(
        "toggle_workflow_state",
        %{"workflow_state" => state, "value_key" => workflow_id},
        socket
      ) do
    %{current_user: actor, project: project_id} = socket.assigns

    workflow_id
    |> Workflows.get_workflow!(include: [:triggers])
    |> Workflows.update_triggers_enabled_state(state)
    |> Helpers.save_workflow(actor)
    |> case do
      {:ok, _workflow} ->
        {:noreply,
         socket
         |> put_flash(:info, "Workflow updated")
         |> push_patch(to: ~p"/projects/#{project_id}/w")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Failed to update workflow. Please try again."
         )
         |> push_patch(to: ~p"/projects/#{project_id}/w")}
    end
  end

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
    %{
      project: project,
      can_delete_workflow: can_delete_workflow?,
      current_user: user
    } = socket.assigns

    if can_delete_workflow? do
      Workflows.get_workflow!(id)
      |> Workflows.mark_for_deletion(user)
      |> case do
        {:ok, _} ->
          {
            :noreply,
            socket
            |> assign(workflows: Workflows.get_workflows_for(project))
            |> put_flash(:info, "Workflow successfully deleted.")
            |> push_patch(to: "/projects/#{project.id}/w")
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

  defp check_workflow_and_run_limits(assigns, project_id) do
    assigns
    |> assign(
      workflow_creation_limit_error: limit_workflow_creation_error(project_id)
    )
    |> LiveHelpers.check_limits(project_id)
  end

  defp limit_workflow_creation_error(project_id) do
    case WorkflowUsageLimiter.limit_workflow_creation(project_id) do
      :ok ->
        nil

      {:error, _reason, %{text: error_msg}} ->
        error_msg
    end
  end
end
