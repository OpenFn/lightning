defmodule LightningWeb.RunLive.Index do
  @moduledoc """
  Index Liveview for Runs
  """
  use LightningWeb, :live_view

  import Ecto.Changeset, only: [get_change: 2]

  alias Lightning.Invocation
  alias Lightning.Invocation.Step
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.WorkOrders
  alias Lightning.WorkOrders.Events
  alias Lightning.WorkOrders.SearchParams
  alias LightningWeb.RunLive.Components
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView.JS

  @filters_types %{
    search_term: :string,
    id: :boolean,
    body: :boolean,
    log: :boolean,
    workflow_id: :string,
    workorder_id: :string,
    date_after: :utc_datetime,
    date_before: :utc_datetime,
    wo_date_after: :utc_datetime,
    wo_date_before: :utc_datetime,
    pending: :boolean,
    running: :boolean,
    success: :boolean,
    failed: :boolean,
    crashed: :boolean,
    cancelled: :boolean,
    killed: :boolean,
    exception: :boolean,
    lost: :boolean
  }

  @empty_page %{
    entries: [],
    page_size: 0,
    total_entries: 0,
    page_number: 1,
    total_pages: 0
  }

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(
        params,
        _session,
        %{
          assigns: %{
            current_user: current_user,
            project: project,
            project_user: project_user
          }
        } = socket
      ) do
    WorkOrders.subscribe(project.id)

    workflows =
      Lightning.Workflows.get_workflows_for(project)
      |> Enum.map(&{&1.name || "Untitled", &1.id})

    can_run_workflow =
      ProjectUsers
      |> Permissions.can?(
        :run_workflow,
        current_user,
        project
      )

    can_edit_data_retention =
      ProjectUsers
      |> Permissions.can?(
        :edit_data_retention,
        current_user,
        project_user
      )

    statuses = [
      %{id: :pending, label: "Enqueued"},
      %{id: :running, label: "Running"},
      %{id: :success, label: "Success"},
      %{id: :failed, label: "Failed"},
      %{id: :crashed, label: "Crashed"},
      %{id: :cancelled, label: "Cancelled"},
      %{id: :killed, label: "Killed"},
      %{id: :exception, label: "Exception"},
      %{id: :lost, label: "Lost"}
    ]

    search_fields = [
      %{id: :id, icon: "hero-finger-print-mini", label: "Include IDs"},
      %{id: :body, icon: "hero-document-arrow-down", label: "Include inputs"},
      %{id: :log, icon: "hero-bars-arrow-down-mini", label: "Include run logs"}
    ]

    params = Map.put_new(params, "filters", init_filters())

    {:ok,
     socket
     |> assign(
       workflows: workflows,
       statuses: statuses,
       search_fields: search_fields,
       string_search_limit: Invocation.get_workorders_count_limit(),
       active_menu_item: :runs,
       work_orders: [],
       selected_work_orders: [],
       can_edit_data_retention: can_edit_data_retention,
       can_run_workflow: can_run_workflow,
       pagination_path: &pagination_path(socket, project, &1),
       filters: params["filters"]
     )}
  end

  defp init_filters,
    do: %{
      "workflow_id" => "",
      "search_term" => "",
      "body" => "true",
      "log" => "true",
      "date_after" =>
        Timex.now() |> Timex.shift(days: -30) |> DateTime.to_string(),
      "date_before" => "",
      "wo_date_after" => "",
      "wo_date_before" => ""
    }

  @impl true
  def handle_params(params, _url, socket) do
    %{project: project} = socket.assigns
    filters = Map.get(params, "filters", init_filters())

    {:noreply,
     socket
     |> assign(
       filters: filters,
       page_title: "History",
       step: %Step{},
       filters_changeset: filters_changeset(filters),
       pagination_path: &pagination_path(socket, project, &1, filters),
       page: @empty_page,
       async_page: AsyncResult.loading()
     )
     |> start_async(:load_workorders, fn ->
       monitored_search(project, params)
     end)}
  end

  # returns the search result
  defp monitored_search(project, page_params) do
    span_metadata = %{
      project_id: project.id,
      provided_filters: Map.get(page_params, "filters", %{})
    }

    :telemetry.span(
      [:lightning, :ui, :projects, :history],
      span_metadata,
      fn ->
        search_params =
          Map.get(page_params, "filters", init_filters())
          |> SearchParams.new()

        search_result =
          Invocation.search_workorders(
            project,
            search_params,
            page_params
          )

        {search_result, span_metadata}
      end
    )
  end

  @impl true
  def handle_async(:load_workorders, {:ok, searched_page}, socket) do
    %{async_page: async_page} = socket.assigns

    {:noreply,
     socket
     |> assign(
       page: searched_page,
       async_page: AsyncResult.ok(async_page, searched_page)
     )
     |> maybe_show_selected_workorder_details()}
  end

  def handle_async(:load_workorders, {:exit, reason}, socket) do
    %{async_page: async_page} = socket.assigns

    {:noreply,
     socket
     |> assign(
       page: @empty_page,
       async_page: AsyncResult.failed(async_page, {:exit, reason})
     )}
  end

  @doc """
  Takes a changeset used for querying workorders and checks to see if the given
  filter is present in that changeset. Returns true or false.
  """
  def checked?(changeset, id) do
    case Ecto.Changeset.fetch_field(changeset, id) do
      value when value in [{:changes, true}] ->
        true

      _ ->
        false
    end
  end

  @doc """
  Creates a changeset based on given parameters and the fixed workorder filter types.
  """
  def filters_changeset(params),
    do:
      Ecto.Changeset.cast(
        {%{}, @filters_types},
        params,
        Map.keys(@filters_types)
      )

  @impl true
  def handle_info(%mod{run: run}, socket)
      when mod in [Events.RunCreated, Events.RunUpdated] do
    %{work_order: work_order} =
      Lightning.Repo.preload(
        run,
        [
          work_order: [
            :workflow,
            :dataclip,
            runs: [steps: [:job, :input_dataclip]]
          ]
        ],
        force: true
      )

    {:noreply, update_page(socket, work_order)}
  end

  @impl true
  @doc """
  When a WorkOrderCreated event is detected, we first check to see if the new
  work order is admissible on the page, given the current filters. If it is, we
  add it to the top of the page. If not, nothing happens.
  """
  def handle_info(
        %Events.WorkOrderCreated{work_order: work_order},
        %{assigns: assigns} = socket
      ) do
    %{project: project, filters: filters} = assigns

    params =
      filters
      |> Map.merge(%{"workorder_id" => work_order.id})
      |> SearchParams.new()

    # Note that this may or may not contain the new work order, depending on the filters.
    case Invocation.search_workorders(project, params) do
      %{entries: []} -> {:noreply, socket}
      %{entries: [work_order]} -> {:noreply, append_to_page(socket, work_order)}
    end
  end

  @impl true
  def handle_info(
        %Events.WorkOrderUpdated{work_order: work_order},
        socket
      ) do
    work_order =
      Lightning.Repo.preload(
        work_order,
        [:workflow, :dataclip, runs: [steps: [:job, :input_dataclip]]],
        force: true
      )

    {:noreply, update_page(socket, work_order)}
  end

  @impl true
  def handle_event(
        "rerun",
        %{"run_id" => run_id, "step_id" => step_id},
        socket
      ) do
    if socket.assigns.can_run_workflow do
      WorkOrders.retry(run_id, step_id, created_by: socket.assigns.current_user)

      {:noreply, socket}
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action.")}
    end
  end

  def handle_event("bulk-rerun", attrs, socket) do
    with true <- socket.assigns.can_run_workflow,
         {:ok, count} <- handle_bulk_rerun(socket, attrs) do
      {:noreply,
       socket
       |> put_flash(
         :info,
         "New run#{if count > 1, do: "s", else: ""} enqueued for #{count} workorder#{if count > 1, do: "s", else: ""}"
       )
       |> push_navigate(
         to:
           ~p"/projects/#{socket.assigns.project.id}/history?#{%{filters: socket.assigns.filters}}"
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
           "Oops! The chosen step hasn't been run in the latest runs of any of the selected workorders"
         )}

      {:error, _changes} ->
        {:noreply,
         socket
         |> put_flash(:error, "Oops! an error occured during retries.")}
    end
  end

  def handle_event(
        "toggle_selection",
        %{
          "workorder_id" => workorder_id,
          "selected" => selected?
        },
        socket
      ) do
    %{page: page, selected_work_orders: selected_work_orders} = socket.assigns

    selected? = String.to_existing_atom(selected?)
    workorder = Enum.find(page.entries, &(&1.id == workorder_id))

    work_orders =
      if selected? and nil != workorder do
        selected_workorder = %Lightning.WorkOrder{
          id: workorder.id,
          workflow_id: workorder.workflow_id
        }

        [selected_workorder | selected_work_orders]
      else
        {_wo, rest} =
          Enum.split_with(selected_work_orders, &(&1.id == workorder_id))

        rest
      end

    {:noreply, assign(socket, selected_work_orders: work_orders)}
  end

  def handle_event(
        "toggle_all_selections",
        %{"all_selections" => selection},
        %{assigns: %{page: page}} = socket
      ) do
    selection = String.to_existing_atom(selection)

    work_orders =
      if selection do
        page.entries
        |> Enum.filter(fn wo -> is_nil(wo.dataclip.wiped_at) end)
        |> Enum.map(fn entry ->
          %Lightning.WorkOrder{id: entry.id, workflow_id: entry.workflow_id}
        end)
      else
        []
      end

    {:noreply, assign(socket, selected_work_orders: work_orders)}
  end

  def handle_event("apply_filters", %{"filters" => new_filters}, socket) do
    %{filters: prev_filters, project: project} = socket.assigns

    filters =
      Map.merge(prev_filters, new_filters)
      |> Map.reject(fn {_k, v} -> Enum.member?(["false", ""], v) end)

    {:noreply,
     socket
     |> assign(filters: filters)
     |> push_patch(
       to: ~p"/projects/#{project.id}/history?#{%{filters: filters}}"
     )}
  end

  defp find_workflow_name(workflows, workflow_id) do
    Enum.find_value(workflows, fn {name, id} ->
      if id == workflow_id do
        name
      end
    end)
  end

  defp handle_bulk_rerun(socket, %{"type" => "selected", "job" => job_id}) do
    socket.assigns.selected_work_orders
    |> WorkOrders.retry_many(job_id, created_by: socket.assigns.current_user)
  end

  defp handle_bulk_rerun(socket, %{"type" => "all", "job" => job_id}) do
    filter = SearchParams.new(socket.assigns.filters)

    socket.assigns.project
    |> Invocation.search_workorders_query(filter)
    |> Invocation.exclude_wiped_dataclips()
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
    |> Invocation.exclude_wiped_dataclips()
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

  defp maybe_humanize_date(date) do
    date && Timex.format!(date, "{D}/{M}/{YY}")
  end

  defp append_to_page(socket, workorder) do
    %{page: page, async_page: async_page} = socket.assigns

    new_page =
      %{
        page
        | entries: [workorder] ++ page.entries,
          page_size: page.page_size + 1,
          total_entries: page.total_entries + 1
      }

    assign(socket,
      async_page: AsyncResult.ok(async_page, new_page),
      page: new_page
    )
  end

  defp update_page(socket, workorder) do
    %{page: page, async_page: async_page} = socket.assigns

    updated_page = %{page | entries: update_workorder(page.entries, workorder)}

    assign(socket,
      async_page: AsyncResult.ok(async_page, updated_page),
      page: updated_page
    )
  end

  defp update_workorder(entries, workorder) do
    entries
    |> Enum.reduce([], fn entry, acc ->
      if entry.id == workorder.id do
        [workorder | acc]
      else
        [entry | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp pagination_path(socket, project, route_params, filters \\ %{}) do
    Routes.project_run_index_path(
      socket,
      :index,
      project,
      Keyword.merge(route_params, filters: filters)
    )
  end

  defp maybe_show_selected_workorder_details(socket) do
    %{filters_changeset: changeset} = socket.assigns

    if workorder_id = Ecto.Changeset.get_change(changeset, :workorder_id) do
      send_update(LightningWeb.RunLive.WorkOrderComponent,
        id: workorder_id,
        show_details: true,
        show_prev_runs: true
      )
    end

    socket
  end
end
