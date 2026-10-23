defmodule LightningWeb.RunLive.Index do
  @moduledoc """
  Index Liveview for Runs
  """
  use LightningWeb, :live_view

  import Ecto.Changeset, only: [get_change: 2]

  alias Lightning.Invocation
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Run
  alias Lightning.Runs
  alias Lightning.WorkOrder
  alias Lightning.WorkOrders
  alias Lightning.WorkOrders.Events
  alias Lightning.WorkOrders.SearchParams
  alias LightningWeb.RunLive.CancelHelper

  alias Phoenix.LiveView.AsyncResult

  require Logger

  @filters_types %{
    search_term: :string,
    id: :boolean,
    body: :boolean,
    log: :boolean,
    dataclip_name: :boolean,
    workflow_id: :string,
    workorder_id: :string,
    date_after: :utc_datetime,
    date_before: :utc_datetime,
    wo_date_after: :utc_datetime,
    wo_date_before: :utc_datetime,
    run_date_after: :utc_datetime,
    run_date_before: :utc_datetime,
    run_status: {:array, :string},
    pending: :boolean,
    running: :boolean,
    success: :boolean,
    failed: :boolean,
    crashed: :boolean,
    cancelled: :boolean,
    killed: :boolean,
    exception: :boolean,
    lost: :boolean,
    rejected: :boolean,
    sort_by: :string,
    sort_direction: :string,
    error_signature_exit_reason: :string,
    error_signature_error_type: :string,
    error_signature_job_id: :string
  }

  # The status filters and the search toggles, in the order the page lists them.
  @statuses ~w(pending running success failed crashed cancelled killed exception lost rejected)a
  @search_fields ~w(id dataclip_name body log)a
  @known_kill_errors ~w(SecurityError ImportError TimeoutError OOMError StateTooLargeError)

  @empty_page %{
    entries: [],
    page_size: 10,
    total_entries: 0,
    page_number: 1,
    total_pages: 0
  }

  on_mount {LightningWeb.Hooks, :project_scope}
  on_mount {LightningWeb.Hooks, :check_limits}

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
      Lightning.Workflows.get_workflows_for(project, include: [:jobs])
      |> Enum.map(fn workflow ->
        %{
          id: workflow.id,
          name: workflow.name || "Untitled",
          jobs:
            workflow.jobs
            |> Enum.sort_by(& &1.name)
            |> Enum.map(&%{id: &1.id, name: &1.name})
        }
      end)

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

    params = Map.put_new(params, "filters", init_filters())

    {:ok,
     socket
     |> assign(
       workflows: workflows,
       string_search_limit: Invocation.get_workorders_count_limit(),
       channels_enabled:
         Lightning.Accounts.experimental_features_enabled?(current_user),
       active_menu_item: :runs,
       can_edit_data_retention: can_edit_data_retention,
       can_run_workflow: can_run_workflow,
       filters: params["filters"],
       channel_logs: nil,
       reported_kills: MapSet.new(),
       search_again: false
     )}
  end

  # --- Channel logs props ---

  # The shape the design system's ChannelLogRow type expects: the path and
  # the error picked from the events here, as the old component did.
  defp channel_log_rows(page) do
    Enum.map(page.entries, fn entry ->
      %{
        id: entry.id,
        requestId: entry.request_id,
        channelId: entry.channel_id,
        channelName: entry.channel.name,
        startedAt: entry.started_at,
        state: entry.state,
        requestPath: event_field(entry, :destination_response, :request_path),
        errorMessage: event_field(entry, :error, :error_message)
      }
    end)
  end

  defp event_field(channel_request, event_type, field) do
    case Enum.find(channel_request.channel_events, &(&1.type == event_type)) do
      nil -> nil
      event -> Map.get(event, field)
    end
  end

  defp page_json(page),
    do: %{
      number: page.page_number,
      size: page.page_size,
      totalEntries: page.total_entries
    }

  # --- Work orders props ---

  # The shape the design system's HistoryWorkOrdersPageProps expect, minus
  # the handlers. Sent whole on every change, live updates included.
  defp work_orders_props(assigns) do
    %{project: project, filters: filters} = assigns

    %{
      project: %{
        id: project.id,
        parentId: project.parent_id,
        color: project.color
      },
      projectLabel: assigns.project_label,
      channelsEnabled: assigns.channels_enabled,
      workOrdersHref: ~p"/projects/#{project}/history",
      channelLogsHref: ~p"/projects/#{project}/history/channels",
      workflows: assigns.workflows,
      filters:
        filters_json(
          assigns.filters_changeset,
          assigns.error_signature_job_name
        ),
      rows: Enum.map(assigns.page.entries, &work_order_row(&1, assigns)),
      state: async_state(assigns.async_page),
      page: page_json(assigns.page),
      sort: %{
        key: Map.get(filters, "sort_by") || "last_activity",
        direction: Map.get(filters, "sort_direction") || "desc"
      },
      searchLimit: assigns.string_search_limit,
      canRunWorkflow: assigns.can_run_workflow,
      dataStorageHref:
        if(assigns.can_edit_data_retention,
          do: ~p"/projects/#{project}/settings#data-storage"
        )
    }
  end

  defp filters_json(changeset, error_signature_job_name) do
    change = &get_change(changeset, &1)

    %{
      workflowId: change.(:workflow_id),
      statuses: Enum.filter(@statuses, &(change.(&1) == true)),
      receivedAfter: change.(:wo_date_after),
      receivedBefore: change.(:wo_date_before),
      activityAfter: change.(:date_after),
      activityBefore: change.(:date_before),
      runStatuses: change.(:run_status) || [],
      runCreatedAfter: change.(:run_date_after),
      runCreatedBefore: change.(:run_date_before),
      workorderId: change.(:workorder_id),
      errorSignature:
        if(exit_reason = change.(:error_signature_exit_reason),
          do: %{
            exitReason: exit_reason,
            errorType: change.(:error_signature_error_type),
            jobId: change.(:error_signature_job_id),
            jobName: error_signature_job_name
          }
        ),
      searchTerm: change.(:search_term) || "",
      searchFields: Enum.filter(@search_fields, &(change.(&1) == true))
    }
  end

  defp async_state(%AsyncResult{failed: failed}) when not is_nil(failed),
    do: "error"

  defp async_state(%AsyncResult{ok?: true}), do: "ready"
  defp async_state(_loading), do: "loading"

  defp work_order_row(work_order, assigns) do
    %{project: project} = assigns
    last_run = List.first(work_order.runs)

    %{
      id: work_order.id,
      workflowId: work_order.workflow_id,
      workflowName:
        cond do
          work_order.snapshot -> work_order.snapshot.name
          work_order.workflow -> work_order.workflow.name
          true -> "Untitled"
        end,
      state: work_order.state,
      dataclipId: work_order.dataclip_id,
      dataclipWiped: not is_nil(work_order.dataclip.wiped_at),
      insertedAt: work_order.inserted_at,
      lastActivity: work_order.last_activity,
      runs: Enum.map(work_order.runs, &run_row(&1, work_order, assigns)),
      href:
        ~p"/projects/#{project}/history?#{%{filters: %{workorder_id: work_order.id}}}",
      workflowHref:
        if(last_run,
          do:
            ~p"/projects/#{project}/w/#{work_order.workflow_id}?#{maybe_add_snapshot_version(%{run: last_run.id}, work_order.snapshot.lock_version, work_order.workflow.lock_version, assigns.channels_enabled)}"
        ),
      dataclipHref:
        ~p"/projects/#{project}/dataclips/#{work_order.dataclip_id}/show"
    }
  end

  defp run_row(run, work_order, assigns) do
    %{
      id: run.id,
      state: run.state,
      insertedAt: run.inserted_at,
      claimedAt: run.claimed_at,
      startedAt: run.started_at,
      finishedAt: run.finished_at,
      updatedAt: run.updated_at,
      href: ~p"/projects/#{assigns.project}/runs/#{run}",
      steps: Enum.map(run.steps, &step_row(&1, run, work_order, assigns))
    }
  end

  # The page shows an unknown kill like an OOM, so say that one turned up,
  # once per step as the page loads it rather than on every render.
  defp report_unknown_kills(socket, work_orders) do
    %{reported_kills: reported} = socket.assigns

    steps =
      for %{runs: runs} <- work_orders,
          %{steps: steps} <- runs,
          %{exit_reason: "kill", error_type: error_type} = step <- steps,
          error_type not in @known_kill_errors,
          not MapSet.member?(reported, step.id),
          do: step

    for %{error_type: error_type} <- steps do
      Logger.warning("Unknown kill error_type: #{inspect(error_type)}")

      Lightning.Sentry.capture_message("Unknown kill error_type",
        level: :warning,
        extra: %{error_type: error_type}
      )
    end

    assign(socket,
      reported_kills: MapSet.union(reported, MapSet.new(steps, & &1.id))
    )
  end

  # A step may have no snapshot, or one without its job: the name falls back
  # to the job itself, which may be deleted, and the link to the workflow as
  # it is now.
  defp step_row(step, run, work_order, assigns) do
    %{project: project} = assigns

    snapshot =
      step.snapshot ||
        %{jobs: [], lock_version: work_order.workflow.lock_version}

    snapshot_job = Enum.find(snapshot.jobs, &(&1.id == step.job_id))

    inspect_params =
      maybe_add_snapshot_version(
        %{run: run.id, panel: "editor", job: step.job_id},
        snapshot.lock_version,
        work_order.workflow.lock_version,
        assigns.channels_enabled
      )

    %{
      id: step.id,
      jobId: step.job_id,
      # A job gone from both, named by its id as the error signature chip does.
      jobName:
        (snapshot_job || step.job || %{name: String.slice(step.job_id, 0, 8)}).name,
      exitReason: step.exit_reason,
      errorType: step.error_type,
      startedAt: step.started_at,
      finishedAt: step.finished_at,
      # Reused from an earlier run, so it's older than this one.
      cloned: DateTime.compare(step.inserted_at, run.inserted_at) == :lt,
      inputWiped:
        is_nil(step.input_dataclip) or
          not is_nil(step.input_dataclip.wiped_at),
      jobDeleted: is_nil(step.job),
      href: ~p"/projects/#{project}/runs/#{run}?#{%{step: step.id}}",
      inspectHref:
        ~p"/projects/#{project}/w/#{work_order.workflow_id}?#{inspect_params}" <>
          "#log"
    }
  end

  # A run of the current version needs no pin. With experimental features a
  # historical run is pinned with `?as_run=`, which resolves the run's own
  # snapshot and so works for runs that were never released; without them it
  # is `?v=` and the snapshot's lock_version.
  defp maybe_add_snapshot_version(
         params,
         snapshot_version,
         workflow_version,
         experimental_features
       ) do
    cond do
      snapshot_version == workflow_version ->
        params

      experimental_features ->
        Map.merge(params, %{as_run: params[:run]})

      true ->
        Map.merge(params, %{v: snapshot_version})
    end
  end

  defp init_filters,
    do: %{
      "workflow_id" => "",
      "search_term" => "",
      "log" => "true",
      "date_after" =>
        Timex.now() |> Timex.shift(days: -30) |> DateTime.to_string(),
      "date_before" => "",
      "wo_date_after" => "",
      "wo_date_before" => "",
      "sort_by" => "last_activity",
      "sort_direction" => "desc"
    }

  # The channel logs tab is the design system's page: the list, the channel
  # filter and the page come from the URL, as the old component read them.
  @impl true
  def handle_params(
        params,
        _url,
        %{assigns: %{live_action: :channel_logs, project: project}} = socket
      ) do
    socket =
      socket
      |> assign(page_title: "History")
      |> assign_new(:channels, fn ->
        Lightning.Channels.list_channels_for_project(project.id)
      end)

    search_params = channel_search_params(params, socket.assigns.channels)

    {:noreply,
     assign(socket,
       channel_logs: %{
         channel_id: search_params.channel_id,
         page:
           Lightning.Channels.list_channel_requests(
             project,
             search_params,
             Map.take(params, ["page"])
           )
       }
     )}
  end

  # The work orders tab is the design system's page too: the search, the
  # sort and the page come from the URL's `filters[…]` and `page`.
  def handle_params(params, _url, socket) do
    %{project: project} = socket.assigns
    filters = Map.get(params, "filters", init_filters())

    {:noreply,
     socket
     |> assign(
       filters: filters,
       page_title: "History",
       filters_changeset: filters_changeset(filters),
       error_signature_job_name:
         Lightning.Jobs.get_job_name(
           project.id,
           filters["error_signature_job_id"]
         ),
       page: @empty_page,
       async_page: AsyncResult.loading(),
       page_params: params,
       search_again: false
     )
     |> load_workorders()}
  end

  defp load_workorders(socket) do
    %{project: project, page_params: params} = socket.assigns

    start_async(socket, :load_workorders, fn ->
      perform_search(project, params)
    end)
  end

  # A channel id from the URL only counts when it is one of this project's
  # channels; anything else, and any non-map filters, means "any channel".
  defp channel_search_params(params, channels) do
    filters =
      case params["filters"] do
        %{} = filters -> filters
        _ -> %{}
      end

    search_params = Lightning.Channels.SearchParams.new(filters)

    if Enum.any?(channels, &(&1.id == search_params.channel_id)) do
      search_params
    else
      %{search_params | channel_id: nil}
    end
  end

  # returns the search result
  defp perform_search(project, page_params) do
    LightningWeb.Telemetry.with_span(
      [:lightning, :ui, :projects, :history],
      %{
        project_id: project.id,
        provided_filters: Map.get(page_params, "filters", %{})
      },
      fn ->
        search_params =
          Map.get(page_params, "filters", init_filters())
          |> SearchParams.new()

        Invocation.search_workorders(
          project,
          search_params,
          page_params
        )
      end
    )
  end

  @impl true
  def handle_async(:load_workorders, {:ok, searched_page}, socket) do
    %{async_page: async_page, search_again: search_again} = socket.assigns

    socket =
      socket
      |> report_unknown_kills(searched_page.entries)
      |> assign(
        page: searched_page,
        async_page: AsyncResult.ok(async_page, searched_page),
        search_again: false
      )

    # Shown at once, then searched once more, no longer loading, so events
    # update the rows meanwhile: a busy project can't keep the page loading.
    {:noreply, if(search_again, do: load_workorders(socket), else: socket)}
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
  Creates a changeset based on given parameters and the fixed workorder filter types.
  """
  def filters_changeset(params),
    do:
      Ecto.Changeset.cast(
        {%{}, @filters_types},
        params,
        Map.keys(@filters_types)
      )

  # A change while the rows are loading has no row to update yet, and the
  # search may have read the rows before it: a background retry or cancel
  # often lands while the page it navigated to is still searching. So the
  # search runs again once it has answered.
  @impl true
  def handle_info(
        %mod{},
        %{assigns: %{live_action: :index, async_page: %{loading: true}}} = socket
      )
      when mod in [
             Events.RunCreated,
             Events.RunUpdated,
             Events.WorkOrderCreated,
             Events.WorkOrderUpdated
           ] do
    {:noreply, assign(socket, search_again: true)}
  end

  def handle_info(%mod{run: run}, %{assigns: %{live_action: :index}} = socket)
      when mod in [Events.RunCreated, Events.RunUpdated] do
    work_order = Invocation.reload_workorder_for_list(run)

    {:noreply, socket |> update_page(work_order)}
  end

  @impl true
  @doc """
  When a WorkOrderCreated event is detected, we first check to see if the new
  work order is admissible on the page, given the current filters. If it is, we
  add it to the top of the page. If not, nothing happens.
  """
  def handle_info(
        %Events.WorkOrderCreated{work_order: work_order},
        %{assigns: %{live_action: :index}} = socket
      ) do
    %{project: project, filters: filters} = socket.assigns

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
        %{assigns: %{live_action: :index}} = socket
      ) do
    work_order = Invocation.reload_workorder_for_list(work_order)

    {:noreply, socket |> update_page(work_order)}
  end

  # Work order / run events are irrelevant on the channel logs tab
  def handle_info(%mod{}, %{assigns: %{live_action: :channel_logs}} = socket)
      when mod in [
             Events.RunCreated,
             Events.RunUpdated,
             Events.WorkOrderCreated,
             Events.WorkOrderUpdated
           ] do
    {:noreply, socket}
  end

  # Each event below answers the page: `{:reply, %{}, socket}` when it
  # worked (the flash says what happened), `reply_error/2` when it didn't.
  @impl true
  def handle_event(
        "rerun",
        %{"run_id" => run_id, "step_id" => step_id},
        socket
      ) do
    require_run_workflow(socket, fn ->
      %{project: %{id: project_id}, current_user: current_user} = socket.assigns

      # Scope the browser-supplied run_id to this project before retrying, so an
      # editor of one project can't retry (execute) another project's run. Also
      # reject a malformed id or a step that isn't part of the run rather than
      # let those crash the query.
      with true <- Lightning.Validators.valid_uuid?(run_id),
           %Run{steps: steps} <-
             Runs.get_for_project(run_id, project_id, include: [:steps]),
           true <- Enum.any?(steps, &(&1.id == step_id)),
           :ok <- WorkOrders.limit_run_creation(project_id),
           {:ok, _run} <-
             WorkOrders.retry(run_id, step_id, created_by: current_user) do
        {:reply, %{}, socket}
      else
        result when result in [false, nil] ->
          reply_error(socket, "Run not found.")

        {:error, _reason, %{text: error_text}} ->
          reply_error(socket, error_text)

        {:error, :workflow_deleted} ->
          reply_error(socket, "Runs for deleted workflows cannot be retried")

        {:error, _changeset} ->
          reply_error(socket, "Oops! an error occured during retry.")
      end
    end)
  end

  def handle_event("bulk-rerun", attrs, socket) do
    require_run_workflow(socket, fn ->
      case handle_bulk_rerun(socket, attrs) do
        {:ok, count, discarded_count} ->
          {:reply, %{},
           socket
           |> put_flash(:info, rerun_message(count, discarded_count))
           |> push_navigate(to: history_path(socket))}

        :not_found ->
          reply_error(socket, "Work order not found.")

        {:error, _changes} ->
          reply_error(socket, "Oops! an error occured during retries.")

        {:error, _reason, %{text: error_message}} ->
          reply_error(socket, error_message)
      end
    end)
  end

  # Retry and Retry from ask before opening their modal, so a project over
  # its run limit hears why on the click.
  def handle_event("validate_bulk_rerun", %{"count" => count}, socket)
      when is_integer(count) do
    case WorkOrders.limit_run_creation(socket.assigns.project.id, count) do
      {:error, _reason, %{text: error_message}} ->
        reply_error(socket, error_message)

      _ok ->
        {:reply, %{}, socket}
    end
  end

  def handle_event("validate_bulk_rerun", _params, socket),
    do: reply_error(socket, "Invalid request")

  def handle_event("bulk-cancel", attrs, socket) do
    require_run_workflow(socket, fn ->
      case handle_bulk_cancel(socket, attrs) do
        {:ok, cancelled} ->
          message =
            "Cancelled #{cancelled} run#{if cancelled != 1, do: "s"}"

          {:reply, %{},
           socket
           |> put_flash(:info, message)
           |> push_navigate(to: history_path(socket))}

        {:async, count} ->
          message =
            "Cancelling runs for #{count} work order#{if count != 1, do: "s"} in the background..."

          {:reply, %{},
           socket
           |> put_flash(:info, message)
           |> push_navigate(to: history_path(socket))}

        :not_found ->
          reply_error(socket, "Work order not found.")

        {:error, _reason} ->
          reply_error(socket, "An error occurred while cancelling.")
      end
    end)
  end

  def handle_event(
        "cancel",
        %{"workorder_id" => workorder_id},
        socket
      ) do
    require_run_workflow(socket, fn ->
      with true <- Lightning.Validators.valid_uuid?(workorder_id),
           {:ok, n} when n > 0 <-
             WorkOrders.cancel_many(
               [%WorkOrder{id: workorder_id}],
               project_id: socket.assigns.project.id
             ) do
        {:reply, %{}, put_flash(socket, :info, "Work order cancelled.")}
      else
        false ->
          reply_error(socket, "Work order not found.")

        {:ok, 0} ->
          {:reply, %{},
           put_flash(
             socket,
             :info,
             "Work order could not be cancelled" <>
               " — it is no longer pending."
           )}

        {:error, _reason} ->
          reply_error(socket, "An error occurred while cancelling.")
      end
    end)
  end

  def handle_event("cancel-run", %{"run_id" => run_id}, socket) do
    require_run_workflow(socket, fn ->
      case CancelHelper.cancel_run(run_id, socket.assigns.project.id) do
        {:ok, _run} ->
          {:reply, %{}, put_flash(socket, :info, "Run cancelled.")}

        {:error, :not_found} ->
          reply_error(socket, "Run not found.")

        {:error, :not_available} ->
          {:reply, %{},
           put_flash(
             socket,
             :info,
             "Run could not be cancelled" <>
               " — it is no longer available."
           )}

        {:error, _} ->
          reply_error(socket, "An error occurred while cancelling.")
      end
    end)
  end

  def handle_event("confirm-export", _params, socket) do
    require_run_workflow(socket, fn ->
      %{filters: filters, project: project, current_user: current_user} =
        socket.assigns

      search_params = SearchParams.new(filters)

      case Invocation.export_workorders(project, current_user, search_params) do
        {:ok, _} ->
          {:reply, %{},
           put_flash(
             socket,
             :info,
             "History export started successfully. You will be notified by email after completion."
           )}

        {:error, _failed_operation, _reason, _changes} ->
          reply_error(socket, "Failed to start export. Please try again.")
      end
    end)
  end

  defp rerun_message(count, discarded_count) do
    message =
      "New run#{if count > 1, do: "s"} enqueued for #{count} workorder#{if count > 1, do: "s"}"

    if discarded_count > 0 do
      "#{message} (#{discarded_count} were discarded due to wiped dataclip/workflow being deleted)"
    else
      message
    end
  end

  defp history_path(socket) do
    ~p"/projects/#{socket.assigns.project.id}/history?#{%{filters: socket.assigns.filters}}"
  end

  # Every workflow-mutating action on this page needs the run-workflow
  # permission. Runs fun when the user has it, otherwise replies with the
  # standard not-authorized error.
  defp require_run_workflow(socket, fun) do
    if socket.assigns.can_run_workflow do
      fun.()
    else
      reply_error(socket, "You are not authorized to perform this action.")
    end
  end

  defp handle_bulk_rerun(
         socket,
         %{"type" => "selected", "workorder_ids" => ids} = attrs
       ) do
    with {:ok, work_orders} <- on_this_page(socket, ids) do
      retry_many(socket, work_orders, attrs["job"])
    end
  end

  defp handle_bulk_rerun(socket, %{"type" => "all"} = attrs) do
    filter = SearchParams.new(socket.assigns.filters)

    work_orders =
      Invocation.search_workorders_for_retry(socket.assigns.project, filter)

    retry_many(socket, work_orders, attrs["job"])
  end

  defp handle_bulk_rerun(_socket, _attrs), do: :not_found

  defp retry_many(socket, work_orders, nil) do
    WorkOrders.retry_many(work_orders,
      created_by: socket.assigns.current_user,
      project_id: socket.assigns.project.id
    )
  end

  defp retry_many(socket, work_orders, job_id) do
    cond do
      not Lightning.Validators.valid_uuid?(job_id) ->
        :not_found

      work_orders == [] ->
        {:ok, 0, 0}

      true ->
        WorkOrders.retry_many(work_orders, job_id,
          created_by: socket.assigns.current_user,
          project_id: socket.assigns.project.id
        )
    end
  end

  defp handle_bulk_cancel(socket, %{"type" => "selected", "workorder_ids" => ids}) do
    with {:ok, work_orders} <- on_this_page(socket, ids) do
      WorkOrders.cancel_many(work_orders, project_id: socket.assigns.project.id)
    end
  end

  defp handle_bulk_cancel(socket, %{"type" => "all"}) do
    filter = SearchParams.new(socket.assigns.filters)

    work_orders =
      socket.assigns.project
      |> Invocation.search_workorders_for_cancel(filter)

    case work_orders do
      [] ->
        {:ok, 0}

      _ ->
        case WorkOrders.cancel_many_async(
               work_orders,
               project_id: socket.assigns.project.id
             ) do
          {:ok, _job} -> {:async, length(work_orders)}
          {:error, _} = error -> error
        end
    end
  end

  defp handle_bulk_cancel(_socket, _attrs), do: :not_found

  # The page sends the ids it has ticked. Each must be a work order this page
  # is showing, which also keeps them to this project; otherwise none is acted on.
  defp on_this_page(socket, [_ | _] = ids) do
    work_orders = Enum.filter(socket.assigns.page.entries, &(&1.id in ids))

    if length(work_orders) == length(Enum.uniq(ids)),
      do: {:ok, work_orders},
      else: :not_found
  end

  defp on_this_page(_socket, _ids), do: :not_found

  defp append_to_page(socket, workorder) do
    %{page: page, async_page: async_page} = socket.assigns

    new_page =
      %{
        page
        | entries: [workorder] ++ page.entries,
          page_size: page.page_size + 1,
          total_entries: page.total_entries + 1
      }

    socket
    |> report_unknown_kills([workorder])
    |> assign(
      async_page: AsyncResult.ok(async_page, new_page),
      page: new_page
    )
  end

  defp update_page(socket, workorder) do
    %{page: page, async_page: async_page} = socket.assigns

    updated_page = %{page | entries: update_workorder(page.entries, workorder)}

    socket
    |> report_unknown_kills([workorder])
    |> assign(
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
end
