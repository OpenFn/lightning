defmodule LightningWeb.RunLive.Index do
  @moduledoc """
  Index Liveview for Runs
  """
  use LightningWeb, :live_view

  import Ecto.Changeset, only: [get_change: 2]

  alias Lightning.Workorders.SearchParams
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.WorkOrderService
  alias Lightning.{AttemptService, Invocation}
  alias Lightning.Invocation.Run
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
    failure: :boolean,
    timeout: :boolean,
    crash: :boolean,
    pending: :boolean
  }

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(params, _session, socket) do
    WorkOrderService.subscribe(socket.assigns.project.id)

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
      %{id: :failure, label: "Failure", value: true},
      %{id: :timeout, label: "Timeout", value: true},
      %{id: :crash, label: "Crash", value: true},
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
      "body" => "true",
      "crash" => "true",
      "date_after" =>
        Timex.now() |> Timex.shift(days: -30) |> DateTime.to_string(),
      "date_before" => "",
      "failure" => "true",
      "log" => "true",
      "pending" => "true",
      "search_term" => "",
      "success" => "true",
      "timeout" => "true",
      "wo_date_after" => "",
      "wo_date_before" => "",
      "workflow_id" => ""
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
    filters = Map.get(params, "filters", init_filters()) |> SearchParams.new()

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
        {_, %Lightning.Workorders.Events.AttemptCreated{attempt: attempt}},
        socket
      ) do
    send_update(LightningWeb.RunLive.WorkOrderComponent,
      id: attempt.work_order_id
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {_, %Lightning.Workorders.Events.AttemptUpdated{attempt: attempt}},
        socket
      ) do
    send_update(LightningWeb.RunLive.WorkOrderComponent,
      id: attempt.work_order_id
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:selection_toggled, {%{id: id, workflow_id: workflow_id}, selected?}},
        %{assigns: assigns} = socket
      ) do
    work_orders =
      if selected? do
        [%{id: id, workflow_id: workflow_id} | assigns.selected_work_orders]
      else
        assigns.selected_work_orders -- [%{id: id, workflow_id: workflow_id}]
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
         {:ok, %{attempt_runs: {count, _attempt_runs}}} <-
           handle_bulk_rerun(socket, attrs) do
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
          Map.take(entry, [:id, :workflow_id])
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
    |> workorders_ids()
    |> AttemptService.list_for_rerun_from_job(job_id)
    |> WorkOrderService.retry_attempt_runs(socket.assigns.current_user)
  end

  defp handle_bulk_rerun(socket, %{"type" => "all", "job" => job_id}) do
    filter = SearchParams.new(socket.assigns.filters)

    socket.assigns.project
    |> Invocation.list_work_orders_for_project_query(filter)
    |> Lightning.Repo.all()
    |> Enum.map(& &1.id)
    |> AttemptService.list_for_rerun_from_job(job_id)
    |> WorkOrderService.retry_attempt_runs(socket.assigns.current_user)
  end

  defp handle_bulk_rerun(socket, %{"type" => "selected"}) do
    socket.assigns.selected_work_orders
    |> workorders_ids()
    |> AttemptService.list_for_rerun_from_start()
    |> WorkOrderService.retry_attempt_runs(socket.assigns.current_user)
  end

  defp handle_bulk_rerun(socket, %{"type" => "all"}) do
    filter = SearchParams.new(socket.assigns.filters)

    socket.assigns.project
    |> Invocation.list_work_orders_for_project_query(filter)
    |> Lightning.Repo.all()
    |> Enum.map(& &1.id)
    |> AttemptService.list_for_rerun_from_start()
    |> WorkOrderService.retry_attempt_runs(socket.assigns.current_user)
  end

  defp all_selected?(work_orders, entries) do
    Enum.count(work_orders) == Enum.count(entries)
  end

  defp partially_selected?(work_orders, entries) do
    entries != [] && !none_selected?(work_orders) &&
      !all_selected?(work_orders, entries)
  end

  defp workorders_ids(selected_orders) do
    Enum.map(selected_orders, fn workorder -> workorder.id end)
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
