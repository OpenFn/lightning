defmodule LightningWeb.RunLive.Index do
  @moduledoc """
  Index Liveview for Runs
  """
  use LightningWeb, :live_view

  import Ecto.Changeset, only: [get_change: 2]

  alias Lightning.Invocation
  alias Lightning.Invocation.Run
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.WorkOrders
  alias Lightning.WorkOrders.SearchParams
  alias LightningWeb.RunLive.Components
  alias Phoenix.LiveView.JS

  @filters_types %{
    search_term: :string,
    body: :boolean,
    log: :boolean,
    workflow_id: :string,
    date_after: :utc_datetime,
    date_before: :utc_datetime,
    wo_date_after: :utc_datetime,
    wo_date_before: :utc_datetime,
    success: :boolean,
    failed: :boolean,
    killed: :boolean,
    crashed: :boolean,
    pending: :boolean,
    running: :boolean
  }

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(params, _session, socket) do
    WorkOrders.Events.subscribe(socket.assigns.project.id)

    workflows =
      Lightning.Workflows.get_workflows_for(socket.assigns.project)
      |> Enum.map(&{&1.name || "Untitled", &1.id})

    can_rerun_job =
      ProjectUsers
      |> Permissions.can?(
        :rerun_job,
        socket.assigns.current_user,
        socket.assigns.project
      )

    statuses = [
      %{id: :success, label: "Success", value: true},
      %{id: :failed, label: "Failed", value: true},
      %{id: :running, label: "Running", value: true},
      %{id: :killed, label: "Killed", value: true},
      %{id: :crashed, label: "Crashed", value: true},
      %{id: :pending, label: "Pending", value: true}
    ]

    search_fields = [
      %{id: :body, label: "Input", value: true},
      %{id: :log, label: "Logs", value: true}
    ]

    params = Map.put_new(params, "filters", init_filters())

    {:ok,
     socket
     |> assign(
       workflows: workflows,
       statuses: statuses,
       search_fields: search_fields,
       active_menu_item: :runs,
       work_orders: [],
       selected_work_orders: [],
       can_rerun_job: can_rerun_job,
       pagination_path:
         &Routes.project_run_index_path(
           socket,
           :index,
           socket.assigns.project,
           &1
         ),
       filters: params["filters"]
     )}
  end

  defp init_filters(),
    do: %{
      "workflow_id" => "",
      "search_term" => "",
      "body" => "true",
      "log" => "true",
      "date_after" =>
        Timex.now() |> Timex.shift(days: -30) |> DateTime.to_string(),
      "date_before" => "",
      "wo_date_after" => "",
      "wo_date_before" => "",
      "failed" => "true",
      "crashed" => "true",
      "killed" => "true",
      "pending" => "true",
      "running" => "true",
      "success" => "true"
    }

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(
       page_title: "History",
       run: %Run{},
       filters_changeset: filters_changeset(socket.assigns.filters)
     )
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    provided_filters = Map.get(params, "filters", %{})

    :telemetry.span(
      [:lightning, :ui, :projects, :history],
      %{
        project_id: socket.assigns.project.id,
        provided_filters: provided_filters
      },
      fn ->
        filters =
          Map.get(params, "filters", init_filters()) |> SearchParams.new()

        result =
          socket
          |> assign(
            selected_work_orders: [],
            page:
              Invocation.search_workorders(
                socket.assigns.project,
                filters,
                params
              ),
            filters_changeset:
              params
              |> Map.get("filters", init_filters())
              |> filters_changeset()
          )

        {
          result,
          %{
            project_id: socket.assigns.project.id,
            provided_filters: provided_filters
          }
        }
      end
    )
  end

  def checked(changeset, id) do
    case Ecto.Changeset.fetch_field(changeset, id) do
      value when value in [:error, {:changes, true}] -> true
      _ -> false
    end
  end

  defp filters_changeset(params),
    do:
      Ecto.Changeset.cast(
        {%{}, @filters_types},
        params,
        Map.keys(@filters_types)
      )

  @impl true
  def handle_info(
        %Lightning.WorkOrders.Events.AttemptCreated{attempt: attempt},
        socket
      ) do
    attempt =
      Lightning.Repo.preload(attempt,
        work_order: [:workflow, attempts: [runs: :job]]
      )

    send_update(LightningWeb.RunLive.WorkOrderComponent,
      id: attempt.work_order_id,
      work_order: attempt.work_order
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        %Lightning.WorkOrders.Events.AttemptUpdated{attempt: attempt},
        socket
      ) do
    attempt =
      Lightning.Repo.preload(attempt,
        work_order: [:workflow, attempts: [runs: :job]]
      )

    send_update(LightningWeb.RunLive.WorkOrderComponent,
      id: attempt.work_order_id,
      work_order: attempt.work_order
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        %Lightning.WorkOrders.Events.WorkOrderCreated{work_order: work_order},
        %{assigns: assigns} = socket
      ) do
    params =
      assigns.filters
      |> Map.merge(%{"workorder_id" => work_order.id})
      |> SearchParams.new()

    page_result = Invocation.search_workorders(assigns.project, params)

    page = %{
      assigns.page
      | entries: page_result.entries ++ assigns.page.entries,
        page_size: assigns.page.page_size + page_result.total_entries,
        total_entries: assigns.page.total_entries + page_result.total_entries
    }

    {:noreply, assign(socket, page: page)}
  end

  @impl true
  def handle_info(
        %Lightning.WorkOrders.Events.WorkOrderUpdated{work_order: work_order},
        socket
      ) do
    work_order =
      Lightning.Repo.preload(work_order, [:workflow, attempts: [runs: :job]])

    send_update(LightningWeb.RunLive.WorkOrderComponent,
      id: work_order.id,
      work_order: work_order
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:selection_toggled, {workorder, selected?}},
        %{assigns: assigns} = socket
      ) do
    selected_workorder = %Lightning.WorkOrder{
      id: workorder.id,
      workflow_id: workorder.workflow_id
    }

    work_orders =
      if selected? do
        [selected_workorder | assigns.selected_work_orders]
      else
        assigns.selected_work_orders -- [selected_workorder]
      end

    {:noreply, assign(socket, selected_work_orders: work_orders)}
  end

  @impl true
  def handle_event(
        "rerun",
        %{"attempt_id" => attempt_id, "run_id" => run_id},
        socket
      ) do
    if socket.assigns.can_rerun_job do
      Lightning.WorkOrders.retry(attempt_id, run_id,
        created_by: socket.assigns.current_user
      )

      {:noreply, socket}
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action.")}
    end
  end

  def handle_event("bulk-rerun", attrs, socket) do
    with true <- socket.assigns.can_rerun_job,
         {:ok, count} <- handle_bulk_rerun(socket, attrs) do
      {:noreply,
       socket
       |> put_flash(
         :info,
         "New attempt#{if count > 1, do: "s", else: ""} enqueued for #{count} workorder#{if count > 1, do: "s", else: ""}"
       )
       |> push_navigate(
         to:
           ~p"/projects/#{socket.assigns.project.id}/runs?#{%{filters: socket.assigns.filters}}"
       )}
    else
      false ->
        {:noreply,
         socket
         |> put_flash(:error, "You are not authorized to perform this action.")}

      {:ok, %{reasons: {0, []}}} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Oops! The chosen step hasn't been run in the latest attempts of any of the selected workorders"
         )}

      {:error, _changes} ->
        {:noreply,
         socket
         |> put_flash(:error, "Oops! an error occured during retries.")}
    end
  end

  def handle_event(
        "toggle_all_selections",
        %{"all_selections" => selection},
        %{assigns: %{page: page}} = socket
      ) do
    selection = String.to_existing_atom(selection)

    work_orders =
      if selection do
        Enum.map(page.entries, fn entry ->
          %Lightning.WorkOrder{id: entry.id, workflow_id: entry.workflow_id}
        end)
      else
        []
      end

    update_component_selections(page.entries, selection)

    {:noreply, assign(socket, selected_work_orders: work_orders)}
  end

  def handle_event("apply_filters", %{"filters" => filters}, socket) do
    apply_filters(Map.merge(socket.assigns.filters, filters), socket)
  end

  defp apply_filters(filters, %{assigns: assigns} = socket) do
    update_component_selections(assigns.page.entries, false)

    {:noreply,
     socket
     |> assign(filters_changeset: filters_changeset(filters))
     |> assign(selected_work_orders: [])
     |> assign(filters: filters)
     |> push_patch(
       to: ~p"/projects/#{socket.assigns.project.id}/runs?#{%{filters: filters}}"
     )}
  end

  defp handle_bulk_rerun(socket, %{"type" => "selected", "job" => job_id}) do
    socket.assigns.selected_work_orders
    |> WorkOrders.retry_many(job_id, created_by: socket.assigns.current_user)
  end

  defp handle_bulk_rerun(socket, %{"type" => "all", "job" => job_id}) do
    filter = SearchParams.new(socket.assigns.filters)

    socket.assigns.project
    |> Invocation.search_workorders_query(filter)
    |> Lightning.Repo.all()
    |> WorkOrders.retry_many(job_id, created_by: socket.assigns.current_user)
  end

  defp handle_bulk_rerun(socket, %{"type" => "selected"}) do
    socket.assigns.selected_work_orders
    |> WorkOrders.retry_many(created_by: socket.assigns.current_user)
  end

  defp handle_bulk_rerun(socket, %{"type" => "all"}) do
    filter = SearchParams.new(socket.assigns.filters)

    socket.assigns.project
    |> Invocation.search_workorders_query(filter)
    |> Lightning.Repo.all()
    |> WorkOrders.retry_many(created_by: socket.assigns.current_user)
  end

  defp all_selected?(work_orders, entries) do
    Enum.count(work_orders) == Enum.count(entries)
  end

  defp partially_selected?(work_orders, entries) do
    entries != [] && !none_selected?(work_orders) &&
      !all_selected?(work_orders, entries)
  end

  defp none_selected?(selected_orders) do
    selected_orders == []
  end

  defp selected_workflow_count(selected_orders) do
    selected_orders
    |> Enum.map(fn workorder -> workorder.workflow_id end)
    |> Enum.uniq()
    |> Enum.count()
  end

  defp selected_workorder_count(selected_orders) do
    Enum.count(selected_orders)
  end

  defp update_component_selections(entries, selection) do
    for entry <- entries do
      send_update(LightningWeb.RunLive.WorkOrderComponent,
        id: entry.id,
        entry_selected: selection,
        event: :selection_toggled
      )
    end
  end

  defp maybe_humanize_date(date) do
    date && Timex.format!(date, "{D}/{M}/{YY}")
  end
end
