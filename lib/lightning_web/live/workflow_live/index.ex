defmodule LightningWeb.WorkflowLive.Index do
  @moduledoc false
  use LightningWeb, :live_view

  alias Lightning.DashboardStats
  alias Lightning.Extensions.Message
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.WorkOrder
  alias Lightning.WorkOrders.SearchParams
  alias Lightning.Workflows
  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.WorkflowUsageLimiter
  alias LightningWeb.Live.Helpers.TableHelpers
  alias LightningWeb.WorkflowLive.Helpers

  on_mount {LightningWeb.Hooks, :project_scope}
  on_mount {LightningWeb.Hooks, :check_limits}

  # TODO - make this configurable some day
  @dashboard_period "last 30 days"

  # Columns the dashboard can sort by; client sort params are resolved against
  # this set via TableHelpers.sort_field/3, never interned.
  @sortable_keys ~w(name last_workorder_updated_at workorders_count
                    failed_workorders_count enabled)a

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
       dashboard_period: @dashboard_period,
       lifecycle:
         Lightning.Accounts.experimental_features_enabled?(current_user),
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

    sort_key = params["sort"] || "name"
    sort_direction = params["dir"] || "asc"

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

    field = TableHelpers.sort_field(sort_key, @sortable_keys, :name)
    direction = TableHelpers.sort_direction(sort_direction)

    opts = [order_by: {field, direction}]

    opts =
      if search_term && search_term != "" do
        Keyword.put(opts, :search, search_term)
      else
        opts
      end

    workflows = Workflows.get_workflows_for(project, opts)
    workflow_stats = DashboardStats.get_workflows_stats(workflows)

    sorted_stats =
      if field in [:name, :enabled] do
        # These are ordered by the DB query above; the rest are stats fields
        # sorted in memory.
        workflow_stats
      else
        DashboardStats.sort_workflow_stats(workflow_stats, field, direction)
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

    {:reply, %{},
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

    {:reply, %{},
     socket
     |> push_patch(
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
      project: project,
      search_term: search_term,
      sort_key: sort_key,
      sort_direction: sort_direction
    } = socket.assigns

    query_params = build_query_params(search_term, sort_key, sort_direction)
    redirect = ~p"/projects/#{project}/w?#{query_params}"

    with true <- Permissions.can?(ProjectUsers, :edit_workflow, actor, project),
         %Workflow{} = workflow <-
           Workflows.get_workflow_for_project(project, workflow_id,
             include: [:triggers]
           ) do
      workflow
      |> transition_workflow_state(state, actor)
      |> case do
        {:ok, _workflow} ->
          {:reply, %{},
           socket
           |> put_flash(:info, "Workflow updated")
           |> push_patch(to: redirect)}

        {:error, %Message{text: text}} when is_binary(text) ->
          {:reply, %{},
           socket
           |> put_flash(:error, text)
           |> push_patch(to: redirect)}

        {:error, _reason} ->
          {:reply, %{},
           socket
           |> put_flash(:error, "Failed to update workflow. Please try again.")
           |> push_patch(to: redirect)}
      end
    else
      false ->
        {:reply, %{},
         socket
         |> put_flash(:error, "You are not authorized to perform this action.")
         |> push_patch(to: redirect)}

      nil ->
        {:reply, %{},
         socket
         |> put_flash(:error, "Workflow not found.")
         |> push_patch(to: redirect)}
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

    with true <- can_delete_workflow?,
         %Workflow{} = workflow <-
           Workflows.get_workflow_for_project(project, id) do
      workflow
      |> Workflows.mark_for_deletion(user)
      |> case do
        {:ok, _} ->
          {
            :reply,
            %{},
            socket
            |> put_flash(:info, "Workflow successfully deleted.")
            |> push_patch(to: ~p"/projects/#{project.id}/w?#{query_params}")
          }

        {:error, _changeset} ->
          {:reply, %{}, socket |> put_flash(:error, "Can't delete workflow")}

        # mark_for_deletion runs a Multi, whose failure is a 4-tuple.
        {:error, _step, _reason, _changes} ->
          {:reply, %{}, socket |> put_flash(:error, "Can't delete workflow")}
      end
    else
      false ->
        {:reply, %{},
         socket
         |> put_flash(:error, "You are not authorized to perform this action.")}

      nil ->
        {:reply, %{}, socket |> put_flash(:error, "Workflow not found.")}
    end
  end

  defp transition_workflow_state(workflow, enable?, actor)
       when enable? in [true, "true"] do
    activating? =
      Enum.any?(workflow.triggers, fn trigger -> !trigger.enabled end)

    case WorkflowUsageLimiter.limit_workflow_activation(
           activating?,
           workflow.project_id
         ) do
      :ok -> Workflows.go_live(workflow, actor)
      {:error, _reason, message} -> {:error, message}
    end
  end

  defp transition_workflow_state(workflow, _disable?, actor) do
    Workflows.switch_to_draft(workflow, actor)
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

  # The shape the design system's WorkflowStats type expects: what each row
  # shows, plus the History links behind the counts.
  defp stats_json(stats, project, lifecycle?) do
    wo_filters = wo_filters()
    failed_filters = failed_wo_filters()

    Enum.map(stats, fn stats ->
      workflow = stats.workflow

      %{
        workflow: %{
          id: workflow.id,
          name: workflow.name,
          updatedAt: workflow.updated_at,
          enabled: Helpers.workflow_enabled?(workflow),
          triggerType: trigger_type(workflow)
        },
        triggerEnabled: Enum.any?(workflow.triggers, & &1.enabled),
        state: to_string(workflow.state),
        toggleTooltip: toggle_tooltip(workflow, lifecycle?),
        lastWorkOrder: work_order_json(stats.last_workorder),
        lastFailedAt: stats.last_failed_workorder.updated_at,
        workordersCount: stats.workorders_count,
        failedWorkordersCount: stats.failed_workorders_count,
        stepCount: stats.step_count,
        stepSuccessRate: stats.step_success_rate,
        historyHref:
          history_path(project, Map.put(wo_filters, :workflow_id, workflow.id)),
        failedHistoryHref:
          history_path(
            project,
            Map.put(failed_filters, :workflow_id, workflow.id)
          )
      }
    end)
  end

  defp trigger_type(%{triggers: [%{type: type} | _]}), do: to_string(type)
  defp trigger_type(_workflow), do: "webhook"

  # With the lifecycle on, the switch (in a sandbox) speaks of the state.
  defp toggle_tooltip(workflow, false),
    do: Helpers.workflow_state_tooltip(workflow)

  defp toggle_tooltip(%{state: :live}, true),
    do: "On. Its triggers are answering."

  defp toggle_tooltip(_workflow, true),
    do: "Off. Its triggers are not answering."

  defp work_order_json(%{state: nil}), do: nil

  defp work_order_json(%{state: state, updated_at: updated_at}),
    do: %{state: to_string(state), updatedAt: updated_at}

  defp metrics_json(%DashboardStats.ProjectMetrics{} = metrics) do
    %{
      workOrders: %{
        total: metrics.work_order_metrics.total,
        pending: metrics.work_order_metrics.pending,
        failed: metrics.work_order_metrics.failed,
        failedPercentage: metrics.work_order_metrics.failed_percentage
      },
      runs: %{
        total: metrics.run_metrics.total,
        pending: metrics.run_metrics.pending,
        success: metrics.run_metrics.success,
        successRate: metrics.run_metrics.success_rate
      }
    }
  end

  # One definition of "the work orders behind this number", so every link
  # opens the same window and the same states its count was taken from.
  defp history_path(project, filters) do
    ~p"/projects/#{project}/history?#{%{filters: filters}}"
  end

  defp wo_filters do
    SearchParams.to_uri_params(%{"date_after" => DashboardStats.window_start()})
  end

  defp pending_wo_filters do
    SearchParams.to_uri_params(%{
      "date_after" => DashboardStats.window_start(),
      "pending" => "true",
      "running" => "true"
    })
  end

  defp failed_wo_filters do
    WorkOrder.failure_states()
    |> Map.new(&{to_string(&1), "true"})
    |> Map.put("date_after", DashboardStats.window_start())
    |> SearchParams.to_uri_params()
  end
end
