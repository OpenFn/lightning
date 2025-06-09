defmodule LightningWeb.WorkflowLive.Index do
  @moduledoc false
  use LightningWeb, :live_view

  alias Lightning.DashboardStats
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Workflows
  alias LightningWeb.LiveHelpers
  alias LightningWeb.WorkflowLive.DashboardComponents
  alias LightningWeb.WorkflowLive.Helpers

  on_mount {LightningWeb.Hooks, :project_scope}

  # TODO - make this configurable some day
  @dashboard_period "last 30 days"

  attr :dashboard_period, :string, default: @dashboard_period
  attr :can_create_workflow, :boolean
  attr :can_delete_workflow, :boolean
  attr :workflows, :list
  attr :project, Lightning.Projects.Project
  attr :banner, :map, default: nil
  attr :search_term, :string, default: ""

  @impl true
  def render(%{project: %{id: project_id}} = assigns) do
    assigns = check_run_limits(assigns, project_id)

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
          workflows_stats={@workflows_stats}
          project={@project}
          sort_key={Atom.to_string(@sort_key)}
          sort_direction={Atom.to_string(@sort_direction)}
          search_term={@search_term}
        />
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
       can_create_workflow: can_create_workflow,
       sort_key: "name",
       sort_direction: "asc",
       search_term: ""
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    search_term = params["q"] || ""

    sort_key = params["sort"] |> to_sort_key()
    sort_direction = params["dir"] |> to_sort_direction()

    {:noreply,
     socket
     |> assign(
       search_term: search_term,
       sort_key: sort_key,
       sort_direction: sort_direction
     )
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    %{
      project: project,
      search_term: search_term,
      sort_key: sort_key,
      sort_direction: sort_direction
    } = socket.assigns

    opts = [order_by: {sort_key, sort_direction}]

    opts =
      if search_term && search_term != "" do
        Keyword.put(opts, :search, search_term)
      else
        opts
      end

    workflows = Workflows.get_workflows_for(project, opts)
    workflow_stats = Enum.map(workflows, &DashboardStats.get_workflow_stats/1)

    sorted_stats =
      if sort_key in [:name, :enabled] do
        workflow_stats
      else
        DashboardStats.sort_workflow_stats(
          workflow_stats,
          sort_key,
          sort_direction
        )
      end

    metrics = DashboardStats.aggregate_project_metrics(sorted_stats)

    socket
    |> assign(
      active_menu_item: :overview,
      page_title: "Workflows",
      metrics: metrics,
      workflows_stats: sorted_stats
    )
  end

  @impl true
  def handle_event("search_workflows", %{"value" => search_term}, socket) do
    %{sort_key: sort_key, sort_direction: sort_direction} = socket.assigns

    query_params = build_query_params(search_term, sort_key, sort_direction)

    {:noreply,
     socket
     |> push_patch(
       to: ~p"/projects/#{socket.assigns.project.id}/w?#{query_params}"
     )}
  end

  def handle_event("clear_search", _params, socket) do
    %{sort_key: sort_key, sort_direction: sort_direction} = socket.assigns

    query_params = %{
      sort: sort_key,
      dir: sort_direction
    }

    {:noreply,
     socket
     |> push_patch(
       to: ~p"/projects/#{socket.assigns.project.id}/w?#{query_params}"
     )}
  end

  def handle_event("sort", %{"by" => field}, socket) do
    %{search_term: search_term, sort_direction: current_direction} =
      socket.assigns

    new_direction = switch_sort_direction(current_direction)

    query_params = build_query_params(search_term, field, new_direction)

    {:noreply,
     push_patch(socket,
       to: ~p"/projects/#{socket.assigns.project.id}/w?#{query_params}"
     )}
  end

  def handle_event(
        "toggle_workflow_state",
        %{"workflow_state" => state, "value_key" => workflow_id},
        socket
      ) do
    %{
      current_user: actor,
      project: project_id,
      search_term: search_term,
      sort_key: sort_key,
      sort_direction: sort_direction
    } = socket.assigns

    query_params = build_query_params(search_term, sort_key, sort_direction)

    workflow_id
    |> Workflows.get_workflow!(include: [:triggers])
    |> Workflows.update_triggers_enabled_state(state)
    |> Helpers.save_workflow(actor)
    |> case do
      {:ok, _workflow} ->
        {:noreply,
         socket
         |> put_flash(:info, "Workflow updated")
         |> push_patch(to: ~p"/projects/#{project_id}/w?#{query_params}")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Failed to update workflow. Please try again."
         )
         |> push_patch(to: ~p"/projects/#{project_id}/w?#{query_params}")}
    end
  end

  def handle_event("delete_workflow", %{"id" => id}, socket) do
    %{
      project: project,
      can_delete_workflow: can_delete_workflow?,
      current_user: user,
      search_term: search_term,
      sort_key: sort_key,
      sort_direction: sort_direction
    } = socket.assigns

    query_params = build_query_params(search_term, sort_key, sort_direction)

    if can_delete_workflow? do
      Workflows.get_workflow!(id)
      |> Workflows.mark_for_deletion(user)
      |> case do
        {:ok, _} ->
          {
            :noreply,
            socket
            |> put_flash(:info, "Workflow successfully deleted.")
            |> push_patch(to: ~p"/projects/#{project.id}/w?#{query_params}")
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

  defp build_query_params(search_term, sort_key, sort_direction) do
    base_params = %{
      sort: sort_key,
      dir: sort_direction
    }

    if search_term && search_term != "" do
      Map.put(base_params, :q, search_term)
    else
      base_params
    end
  end

  defp check_run_limits(assigns, project_id) do
    LiveHelpers.check_limits(assigns, project_id)
  end

  defp to_sort_key("name"), do: :name
  defp to_sort_key("enabled"), do: :enabled
  defp to_sort_key("workorders_count"), do: :workorders_count
  defp to_sort_key("failed_workorders_count"), do: :failed_workorders_count
  defp to_sort_key("last_workorder_updated_at"), do: :last_workorder_updated_at
  defp to_sort_key(nil), do: :name

  defp to_sort_direction("asc"), do: :asc
  defp to_sort_direction("desc"), do: :desc
  defp to_sort_direction(nil), do: :asc

  defp switch_sort_direction(:asc), do: :desc
  defp switch_sort_direction(:desc), do: :asc
end
