defmodule LightningWeb.RunLive.Index do
  @moduledoc """
  Index Liveview for Runs
  """
  use LightningWeb, :live_view

  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.WorkOrderService
  alias Lightning.{AttemptService, Invocation}
  alias Lightning.Invocation.Run

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
         )
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

  defp get_query_data(socket, params) do
    search = Map.get(params, "search")

    if search do
      search =
        Enum.map(search, fn {key, value} ->
          {String.to_existing_atom(key), value}
        end)

      statuses = Enum.map(socket.assigns.statuses, fn status -> status.id end)

      search_fields =
        Enum.map(socket.assigns.search_fields, fn search_field ->
          search_field.id
        end)

      statuses =
        Enum.map(search, fn {key, _value} ->
          if key in statuses do
            key
          end
        end)
        |> Enum.filter(fn v -> v end)

      search_fields =
        Enum.map(search, fn {key, value} ->
          if key in search_fields do
            {key, String.to_existing_atom(value)}
          end
        end)
        |> Enum.filter(fn v -> v end)

      remainder =
        Enum.map(search, fn {key, value} ->
          kw = statuses ++ search_fields

          if is_nil(kw[key]) do
            {key, value}
          end
        end)
        |> Enum.filter(fn v -> v end)

      [
        status: statuses,
        search_fields: search_fields,
        search_term: remainder[:search_term],
        workflow_id: remainder[:workflow_id],
        date_after: remainder[:date_after],
        date_before: remainder[:date_before],
        wo_date_after: remainder[:wo_date_after],
        wo_date_before: remainder[:wo_date_before]
      ]
    else
      nil
    end
  end

  defp apply_action(socket, :index, params) do
    data = get_query_data(socket, params)

    socket
    |> assign(
      page:
        Invocation.list_work_orders_for_project(
          socket.assigns.project,
          data,
          params
        ),
      search_changeset:
        params
        |> Map.get("search", %{"search_term" => nil})
        |> search_changeset()
    )
  end

  defp search_changeset(params) do
    {%{},
     %{
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
     }}
    |> Ecto.Changeset.cast(params, [
      :search_term,
      :body,
      :log,
      :workflow_id,
      :date_after,
      :date_before,
      :wo_date_after,
      :wo_date_before,
      :success,
      :failure,
      :timeout,
      :crash,
      :pending
    ])
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

  def handle_event("validate", %{"search" => search_params} = _params, socket) do
    {:noreply,
     socket
     |> assign(search_changeset: search_changeset(search_params))
     |> push_patch(
       to:
         ~p"/projects/#{socket.assigns.project.id}/runs?#{%{search: search_params}}"
     )}
  end
end
