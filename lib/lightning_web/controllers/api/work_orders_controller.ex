defmodule LightningWeb.API.WorkOrdersController do
  @moduledoc """
  API controller for managing work orders.

  ## Query Parameters

  - `page` - Page number (default: 1)
  - `page_size` - Number of items per page (default: 10, at most 100)
  - `state` - Filter by state (comma-separated). Valid values: rejected, pending, running, success, failed, crashed, cancelled, killed, exception, lost
  - `inserted_after` - Filter work orders created after this ISO8601 datetime
  - `inserted_before` - Filter work orders created before this ISO8601 datetime
  - `updated_after` - Filter work orders updated after this ISO8601 datetime
  - `updated_before` - Filter work orders updated before this ISO8601 datetime
  - `project_id` - The project the work orders come from

  The service account must send `project_id` on the list, as these tables grow
  with every run; leaving it out is 400 `invalid_parameter`.

  ## Examples

      GET /api/work_orders?page=1&page_size=20
      GET /api/work_orders?inserted_after=2024-01-01T00:00:00Z
      GET /api/work_orders?inserted_after=2024-01-01T00:00:00Z&inserted_before=2024-12-31T23:59:59Z
      GET /api/projects/:project_id/work_orders?inserted_after=2024-01-01T00:00:00Z

  ## Sample curl requests

  List all work orders:

  ```bash
  curl http://localhost:4000/api/work_orders \\
    -H "Authorization: Bearer $TOKEN"
  ```

  Get a single work order:

  ```bash
  curl http://localhost:4000/api/work_orders/$WORK_ORDER_ID \\
    -H "Authorization: Bearer $TOKEN"
  ```

  Filter by comma-separated IDs:

  ```bash
  curl "http://localhost:4000/api/work_orders?id=$ID1,$ID2" \\
    -H "Authorization: Bearer $TOKEN"
  ```

  Filter by project, workflow, or date range:

  ```bash
  curl "http://localhost:4000/api/work_orders?project_id=$PID&inserted_after=2024-01-01T00:00:00Z" \\
    -H "Authorization: Bearer $TOKEN"
  ```

  Nested route — work orders for a specific project:

  ```bash
  curl http://localhost:4000/api/projects/$PROJECT_ID/work_orders \\
    -H "Authorization: Bearer $TOKEN"
  ```

  """
  use LightningWeb, :controller

  alias Lightning.Invocation
  alias Lightning.Workflows
  alias Lightning.WorkOrders
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters
  alias LightningWeb.API.HistoryBody
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target

  action_fallback FallbackController

  plug LightningWeb.Plugs.AuthorizeAction,
       {:project_users, :access_project}
       when action in [:index, :show]

  plug LightningWeb.Plugs.AuthorizeAction,
       {:history, :run_workflow}
       when action in [:create, :update]

  @doc """
  Lists the work orders of the projects the caller may access, or of one project
  on the nested route, narrowed by the query's filters.

  The caller is authorised before the query is read, so a caller who may not see
  the project learns nothing from its filters. Every bad filter is reported in
  one 400 `invalid_parameter`.

  ## Examples

      GET /api/work_orders?page=2&page_size=50&state=failed,crashed
      GET /api/projects/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d/work_orders?inserted_after=2024-01-01T00:00:00Z
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, %{"project_id" => _} = params) do
    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             {:project_users, :access_project}
           ),
         {:ok, filters} <-
           params
           |> Filters.work_orders(conn.assigns.scope)
           |> Errors.refuse_parameters() do
      list(project, conn, params, filters)
    end
  end

  def index(conn, params) do
    with {:ok, filters} <-
           params
           |> Filters.work_orders(conn.assigns.scope)
           |> Errors.refuse_parameters() do
      list(conn.assigns.scope, conn, params, filters)
    end
  end

  @doc """
  Shows a work order, with its runs, to a caller who may access its project.

  On `/api/work_orders/:id`, `LightningWeb.API.Target.in_project_of/5` decides
  who learns that an id names no work order. On the nested route the path's
  project is checked first, and a work order outside it is 404 `not_found`.

  ## Examples

      GET /api/work_orders/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
      GET /api/projects/a1b2c3d4-.../work_orders/a1b2c3d4-...
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(%{path_params: %{"project_id" => _}} = conn, _params) do
    with {:ok, work_order} <-
           Target.in_project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             {:project_users, :access_project},
             Request.param(conn, "id"),
             &WorkOrders.get_for_project(&1, &2, include: [:workflow, runs: []])
           ) do
      render(conn, "show.json", work_order: work_order, conn: conn)
    end
  end

  def show(conn, _params) do
    with {:ok, work_order} <-
           Target.in_project_of(
             conn.assigns.scope,
             Request.param(conn, "id"),
             {:project_users, :access_project},
             &WorkOrders.get_project_id/1,
             &WorkOrders.get_for_project(&1, &2, include: [:workflow, runs: []])
           ) do
      render(conn, "show.json", work_order: work_order, conn: conn)
    end
  end

  @doc """
  Starts a work order of the path's workflow by hand, as the app's Run button
  does, for a person who may run the project's workflows, and answers 201 with
  it. The `x-meta-work-order-id` and `x-meta-run-id` headers carry its id and
  its run's, as a webhook's answer does.

  The body names where to start, `job_id` or `trigger_id` (the job the
  trigger leads to), and the input, an existing `dataclip_id` or a new `body`,
  `{}` when neither is sent. Every problem with it is reported in one 422; the
  run limits are asked once it is valid.

  ## Examples

      POST /api/projects/a1b2c3d4-.../workflows/e5f6a7b8-.../work_orders
      {"job_id": "c9d0e1f2-...", "body": {"patient": "x"}}
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def create(conn, _params) do
    body = conn.body_params
    user = conn.assigns.current_resource

    with {:ok, workflow} <-
           Target.in_project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             {:history, :run_workflow},
             Request.param(conn, "workflow_id"),
             &Workflows.get_workflow_for_project(&1, &2,
               include: [:jobs, :triggers, :edges, :project]
             )
           ),
         :ok <- Request.check_object(body),
         {:ok, input} <- manual_input(workflow, body),
         :ok <- WorkOrders.limit_run_creation(workflow.project_id),
         {:ok, manual} <-
           input
           |> WorkOrders.Manual.new(
             project: workflow.project,
             workflow: workflow,
             job: input["job"],
             created_by: user
           )
           |> Ecto.Changeset.apply_action(:validate),
         {:ok, work_order} <- WorkOrders.create_for(manual) do
      [run | _] = work_order.runs

      conn
      |> put_status(:created)
      |> put_resp_header("x-meta-work-order-id", work_order.id)
      |> put_resp_header("x-meta-run-id", run.id)
      |> render("created.json", work_order: work_order, conn: conn)
    end
  end

  defp manual_input(workflow, body) do
    unknown =
      Request.unknown_keys(body, [], [:job_id, :trigger_id, :dataclip_id, :body])

    {job, job_entries} = starting_job(workflow, body)
    input_entries = input_entries(workflow, body)

    with :ok <- Errors.refuse(unknown ++ job_entries ++ input_entries) do
      {:ok,
       %{
         "job" => job,
         "dataclip_id" => body["dataclip_id"],
         "body" => Jason.encode!(body["body"] || %{})
       }}
    end
  end

  defp starting_job(workflow, body) do
    case {body["job_id"], body["trigger_id"]} do
      {nil, nil} ->
        {nil,
         [
           Errors.entry(
             ["job_id"],
             {"send job_id or trigger_id", validation: :required}
           )
         ]}

      {_job_id, nil} ->
        with_id(body, "job_id", fn id ->
          Enum.find(workflow.jobs, &(&1.id == id))
        end)

      {nil, trigger_id} when not is_nil(trigger_id) ->
        with_id(body, "trigger_id", &job_after_trigger(workflow, &1))

      {_job_id, _trigger_id} ->
        {nil,
         [
           Errors.entry(
             ["trigger_id"],
             {"can't be sent with job_id", code: :exclusive}
           )
         ]}
    end
  end

  # Looks up the id the body sent at `key` with `find`, once it is a UUID.
  defp with_id(body, key, find) do
    with {:ok, id} <- Request.id({[key], body[key]}),
         %{} = job <- find.(id) do
      {job, []}
    else
      {:error, {:invalid_id, _location}} ->
        {nil, HistoryBody.id_entries(body, key)}

      nil ->
        {nil,
         [
           Errors.entry(
             [key],
             {"is not in this workflow", code: :not_found}
           )
         ]}
    end
  end

  defp job_after_trigger(workflow, trigger_id) do
    with %{} <- Enum.find(workflow.triggers, &(&1.id == trigger_id)),
         %{target_job_id: job_id} <-
           Enum.find(workflow.edges, &(&1.source_trigger_id == trigger_id)) do
      Enum.find(workflow.jobs, &(&1.id == job_id))
    end
  end

  defp input_entries(workflow, body) do
    case {body["dataclip_id"], body["body"]} do
      {nil, nil} ->
        []

      {nil, input} when is_map(input) ->
        []

      {nil, _not_an_object} ->
        [Errors.entry(["body"], {"must be an object", code: :type})]

      {_dataclip_id, nil} ->
        dataclip_entries(workflow, body)

      {_dataclip_id, _input} ->
        [
          Errors.entry(
            ["body"],
            {"can't be sent with dataclip_id", code: :exclusive}
          )
        ]
    end
  end

  defp dataclip_entries(workflow, body) do
    project_id = workflow.project_id

    with {:ok, id} <- Request.id({["dataclip_id"], body["dataclip_id"]}),
         %{project_id: ^project_id} = dataclip <- Invocation.get_dataclip(id) do
      if is_nil(dataclip.wiped_at),
        do: [],
        else: [
          Errors.entry(
            ["dataclip_id"],
            {"has been wiped", code: :dataclip_wiped}
          )
        ]
    else
      {:error, {:invalid_id, _location}} ->
        HistoryBody.id_entries(body, "dataclip_id")

      _missing_or_elsewhere ->
        [Errors.entry(["dataclip_id"], Errors.not_visible())]
    end
  end

  @doc """
  Cancels every run of a work order that no worker has claimed yet, for a
  person who may run the project's workflows. The body is
  `{"state": "cancelled"}`, and the answer is the work order.

  A work order with no such run is 422 `invalid` with a `not_allowed` entry
  at `#/state`. One whose runs are all claimed between the lookup and the
  write is 409 `concurrent_edit`.

  ## Examples

      PATCH /api/work_orders/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
      {"state": "cancelled"}
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, _params) do
    with {:ok, {project_id, work_order}} <-
           Target.in_project_of(
             conn.assigns.scope,
             Request.param(conn, "id"),
             {:history, :run_workflow},
             &WorkOrders.get_project_id/1,
             &with_project_id/2
           ),
         :ok <- HistoryBody.cancel(conn.body_params),
         :ok <- refuse_nothing_waiting(work_order),
         {:ok, work_order} <- cancel(project_id, work_order) do
      render(conn, "show.json", work_order: work_order, conn: conn)
    end
  end

  defp with_project_id(project_id, id) do
    with {:ok, work_order} <-
           WorkOrders.get_for_project(project_id, id, include: [:runs]),
         do: {:ok, {project_id, work_order}}
  end

  defp refuse_nothing_waiting(work_order) do
    if Enum.any?(work_order.runs, &(&1.state == :available)),
      do: :ok,
      else:
        HistoryBody.not_cancellable(
          "can't be set on a work order with no run waiting for a worker"
        )
  end

  defp cancel(project_id, work_order) do
    case WorkOrders.cancel_many([work_order], project_id: project_id) do
      {:ok, 0} -> {:error, :concurrent_edit}
      {:ok, _cancelled} -> WorkOrders.get_for_project(project_id, work_order.id)
      {:error, _reason} = failed -> failed
    end
  end

  defp list(project_or_scope, conn, params, filters) do
    page =
      WorkOrders.paginate_work_orders_for(
        project_or_scope,
        filters,
        Filters.page(params)
      )

    render(conn, "index.json", page: page, filters: filters, conn: conn)
  end
end
