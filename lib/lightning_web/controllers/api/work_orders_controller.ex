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

  alias Lightning.WorkOrders
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target

  action_fallback FallbackController

  plug LightningWeb.Plugs.AuthorizeAction,
       {:project_users, :access_project}

  @doc """
  Lists the work orders of the projects the caller may access, or of one project
  on the nested route, narrowed by the query's filters.

  The caller is authorised before the query is read, so a caller who may not see
  the project learns nothing from its filters. Every bad filter is reported in
  one 400 `invalid_parameter` (error-format spec §9.4).

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
