defmodule LightningWeb.RunLive.Index do
  @moduledoc """
  Index Liveview for Runs
  """
  use LightningWeb, :live_view

  alias Lightning.Workorders.SearchParams
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.WorkOrderService
  alias Lightning.{AttemptService, Invocation}
  alias Lightning.Invocation.Run

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

  on_mount({LightningWeb.Hooks, :project_scope})

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
      %{id: :body, label: "Input body", value: true},
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
      "date_after" => "",
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
    if is_nil(Map.get(params, "filters")) do
      params = Map.put(params, "filters", socket.assigns.filters)

      {:noreply,
       socket
       |> assign(
         page_title: "History",
         run: %Run{},
         filters_changeset: filters_changeset(socket.assigns.filters)
       )
       |> push_patch(
         to: ~p"/projects/#{socket.assigns.project.id}/runs?#{params}"
       )}
    else
      {:noreply,
       socket
       |> assign(
         page_title: "History",
         run: %Run{},
         filters_changeset: filters_changeset(socket.assigns.filters)
       )
       |> apply_action(socket.assigns.live_action, params)}
    end
  end

  defp apply_action(socket, :index, params) do
    filters = Map.get(params, "filters") |> SearchParams.new()

    socket
    |> assign(
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
  def handle_event(
        "rerun",
        %{"attempt_id" => attempt_id, "run_id" => run_id},
        socket
      ) do
    if socket.assigns.can_rerun_job do
      attempt_id
      |> AttemptService.get_for_rerun(run_id)
      |> WorkOrderService.retry_attempt_run(socket.assigns.current_user)

      {:noreply, socket}
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action.")}
    end
  end

  def handle_event("search", %{"filters" => filters} = _params, socket) do
    apply_filters(filters, socket)
  end

  def handle_event("apply_filters", %{"filters" => filters}, socket) do
    apply_filters(Map.merge(socket.assigns.filters, filters), socket)
  end

  defp apply_filters(filters, socket),
    do:
      {:noreply,
       socket
       |> assign(filters_changeset: filters_changeset(filters))
       |> assign(filters: filters)
       |> push_patch(
         to:
           ~p"/projects/#{socket.assigns.project.id}/runs?#{%{filters: filters}}"
       )}
end
