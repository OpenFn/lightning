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
     )
     |> init_search_form(
       statuses: statuses,
       search_fields: search_fields,
       workflows: workflows
     )}
  end

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
    changeset = socket.assigns.changeset

    socket
    |> assign(
      status_options: Ecto.Changeset.fetch_field!(changeset, :status_options),
      search_field_options:
        Ecto.Changeset.fetch_field!(changeset, :search_field_options),
      page:
        Invocation.list_work_orders_for_project(
          socket.assigns.project,
          build_filter(changeset),
          params
        )
    )
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
       to: Routes.project_run_index_path(socket, :index, socket.assigns.project)
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

    {:noreply, socket}
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
       to: Routes.project_run_index_path(socket, :index, socket.assigns.project)
     )}
  end

  # NOTE: this event was previously called "ignore", however there is an
  # issue with form recovery in LiveView where only the first input (if it has
  # a `phx-change` on it) is sent.
  # https://github.com/phoenixframework/phoenix_live_view/issues/2333
  # We have changed the event name to "validate" since that is what
  # the form recovery event will use.
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

    {:noreply, socket}
  end

  defp init_search_form(socket,
         statuses: statuses,
         search_fields: search_fields,
         workflows: workflows
       ) do
    changeset =
      %RunSearchForm{}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_embed(:status_options, statuses)
      |> Ecto.Changeset.put_embed(:search_field_options, search_fields)

    socket
    |> assign(:changeset, changeset)
    |> assign(:workflows, workflows)
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
