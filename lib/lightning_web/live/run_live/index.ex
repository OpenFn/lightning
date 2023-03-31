defmodule LightningWeb.RunLive.Index do
  @moduledoc """
  Index Liveview for Runs
  """
  use LightningWeb, :live_view

  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.WorkOrderService
  alias Lightning.{AttemptService, Invocation, RunSearchForm}
  alias Lightning.Invocation.Run

  alias Lightning.RunSearchForm
  alias Lightning.RunSearchForm.MultiSelectOption

  on_mount({LightningWeb.Hooks, :project_scope})

  @impl true
  def mount(_params, _session, socket) do
    WorkOrderService.subscribe(socket.assigns.project.id)

    workflows =
      Lightning.Workflows.get_workflows_for(socket.assigns.project)
      |> Enum.map(&{&1.name || "Untitled", &1.id})

    can_rerun_job =
      ProjectUsers
      |> Permissions.can(
        :rerun_job,
        socket.assigns.current_user,
        socket.assigns.project
      )

    {:ok,
     socket
     |> assign(
       workflows: workflows,
       active_menu_item: :runs,
       work_orders: [],
       can_rerun_job: can_rerun_job,
       pagination_path:
         &Routes.project_run_index_path(
           socket,
           :index,
           socket.assigns.project,
           &1
         )
     )}
  end

  # .../?..
  # mount
  # handle_params
  #   calculate new assigns
  # render

  # ... a few moment later

  # handle_event "validate"
  #   all it does is make a URI
  #
  #   keep the params
  #   calculate new assigns
  #   push_patch .../?foo=bar

  # handle_params
  #   calculate new assigns
  # render

  # handle_event("validate", params, socket)
  #   params = %{search_term: ..., workflow_ids: [1,2,3], workorder_statuses: [:success, ...]}
  #   probably need a changeset for validation
  # function to turn changeset |> apply_changes() |> do_the_query()

  # ====
  # search[run_status][success]&
  #
  # checkboxes - what does the data look like?
  # status_success => true
  # status_failure => true
  # statuses => [%{selected: true}]

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(
       page_title: "History",
       run: %Run{}
     )
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    # Map.get()
    IO.inspect(params, label: "Params")

    %{"search_term" => "asa"}

    socket =
      socket
      |> assign_search_form(params)

    changeset = socket.assigns.changeset |> IO.inspect()

    socket
    |> assign(
      status_options: Ecto.Changeset.fetch_field!(changeset, :status_options),
      search_field_options: Ecto.Changeset.fetch_field!(changeset, :search_field_options),
      page:
        Invocation.list_work_orders_for_project(
          socket.assigns.project,
          build_filter(changeset),
          params
        ),
      search_changeset:
        params
        |> Map.get("search", %{"search_term" => nil})
        |> search_changeset()
        |> IO.inspect(label: "apply_action :index")
    )
  end

  defp search_changeset(params) do
    {%{}, %{search_term: :string}}
    |> Ecto.Changeset.cast(params, [:search_term])
  end

  @impl true
  def handle_info({:selected_statuses, statuses}, socket) do
    changeset =
      socket.assigns.changeset
      |> Ecto.Changeset.put_embed(:status_options, statuses)

    socket =
      socket
      |> assign(:changeset, changeset)
      |> assign(:status_options, statuses)

    {:noreply,
     socket
     |> push_patch(
       to:
         Routes.project_run_index_path(socket, :index, socket.assigns.project, statuses: statuses)
     )}
  end

  def handle_info({:selected_search_fields, search_fields}, socket) do
    changeset =
      socket.assigns.changeset
      |> Ecto.Changeset.put_embed(:search_field_options, search_fields)

    socket =
      socket
      |> assign(:changeset, changeset)
      |> assign(:search_field_options, search_fields)

    {:noreply,
     socket
     |> push_patch(
       to:
         Routes.project_run_index_path(socket, :index, socket.assigns.project,
           search_fields: search_fields
         )
     )}
  end

  def handle_info(
        {_, %Lightning.Workorders.Events.AttemptCreated{attempt: attempt}},
        socket
      ) do
    send_update(LightningWeb.RunLive.WorkOrderComponent,
      id: attempt.work_order_id
    )

    {:noreply, socket}
  end

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
      AttemptService.get_for_rerun(attempt_id, run_id)
      |> WorkOrderService.retry_attempt_run(socket.assigns.current_user)

      {:noreply, socket}
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action.")}
    end
  end

  def handle_event("validate_2", %{"search" => search_params} = _params, socket) do
    %{"_target" => ["search", "search_term"], "search" => %{"search_term" => "asa"}}
    IO.inspect(search_params, label: "validate_2")

    {:noreply,
     socket
     |> assign(search_changeset: search_changeset(search_params))
     |> push_patch(
       to: ~p"/projects/#{socket.assigns.project.id}/runs?#{%{search: search_params}}"
     )}
  end

  def handle_event(
        "validate",
        %{
          "run_search_form" => %{
            "workflow_id" => workflow_id,
            "date_after" => date_after,
            "date_before" => date_before,
            "wo_date_after" => wo_date_after,
            "wo_date_before" => wo_date_before
          }
        },
        socket
      ) do
    changeset =
      socket.assigns.changeset
      |> Ecto.Changeset.put_change(:workflow_id, workflow_id)
      |> Ecto.Changeset.put_change(:date_after, date_after)
      |> Ecto.Changeset.put_change(:date_before, date_before)
      |> Ecto.Changeset.put_change(:wo_date_after, wo_date_after)
      |> Ecto.Changeset.put_change(:wo_date_before, wo_date_before)

    socket =
      socket
      |> assign(:changeset, changeset)

    {:noreply,
     socket
     |> push_patch(
       to:
         Routes.project_run_index_path(socket, :index, socket.assigns.project,
           workflow: workflow_id,
           after: date_after,
           before: date_before,
           wo_after: wo_date_after,
           wo_before: wo_date_before
         )
     )}
  end

  # NOTE: this event was previously called "ignore", however there is an
  # issue with form recovery in LiveView where only the first input (if it has
  # a `phx-change` on it) is sent.
  # https://github.com/phoenixframework/phoenix_live_view/issues/2333
  # We have changed the event name to "validate" since that is what
  # the form recovery event will use.
  # TODO: see if this is still relevant.
  def handle_event(
        "validate",
        %{"run_search_form" => %{"search_term" => search_term}},
        socket
      ) do
    changeset =
      socket.assigns.changeset
      |> Ecto.Changeset.put_change(:search_term, search_term)

    socket =
      socket
      |> assign(:changeset, changeset)

    {:noreply,
     socket
     |> push_patch(
       to:
         Routes.project_run_index_path(socket, :index, socket.assigns.project,
           search_term: search_term
         )
     )}
  end

  defp assign_search_form(socket, _params) do
    statuses = [
      %MultiSelectOption{id: :success, label: "Success", selected: true},
      %MultiSelectOption{id: :failure, label: "Failure", selected: true},
      %MultiSelectOption{id: :timeout, label: "Timeout", selected: true},
      %MultiSelectOption{id: :crash, label: "Crash", selected: true},
      %MultiSelectOption{id: :pending, label: "Pending", selected: true}
    ]

    search_fields = [
      %MultiSelectOption{id: :body, label: "Input body", selected: true},
      %MultiSelectOption{id: :log, label: "Logs", selected: true}
    ]

    changeset =
      %RunSearchForm{}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_embed(:status_options, statuses)
      |> Ecto.Changeset.put_embed(:search_field_options, search_fields)

    socket
    |> assign(:changeset, changeset)
  end

  # return a keyword  list of criteria:value
  defp build_filter(changeset) do
    status =
      Ecto.Changeset.fetch_field!(changeset, :status_options)
      |> Enum.filter(&(&1.selected in [true, "true"]))
      |> Enum.map(& &1.id)

    search_fields =
      Ecto.Changeset.fetch_field!(changeset, :search_field_options)
      |> Enum.filter(&(&1.selected in [true, "true"]))
      |> Enum.map(& &1.id)

    [
      status: status,
      search_fields: search_fields,
      search_term: Ecto.Changeset.fetch_field!(changeset, :search_term),
      workflow_id: Ecto.Changeset.fetch_field!(changeset, :workflow_id),
      date_after: Ecto.Changeset.fetch_field!(changeset, :date_after),
      date_before: Ecto.Changeset.fetch_field!(changeset, :date_before),
      wo_date_after: Ecto.Changeset.fetch_field!(changeset, :wo_date_after),
      wo_date_before: Ecto.Changeset.fetch_field!(changeset, :wo_date_before)
    ]
  end
end
