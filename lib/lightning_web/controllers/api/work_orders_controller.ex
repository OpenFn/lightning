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
  def index(conn, %{"project_id" => project_id} = params) do
    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             project_id,
             {:project_users, :access_project}
           ),
         {:ok, filters} <-
           params
           |> Filters.work_orders()
           |> Errors.refuse_parameters() do
      list(project, conn, params, filters)
    end
  end

  def index(conn, params) do
    with {:ok, filters} <-
           params
           |> Filters.work_orders()
           |> Errors.refuse_parameters() do
      list(conn.assigns.current_resource, conn, params, filters)
    end
  end

  @doc """
  Shows a work order, with its runs, to a caller who may access its project. A
  work order the caller has no standing on answers 404 `not_found`, as if it
  didn't exist.

  ## Examples

      GET /api/work_orders/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(conn, %{"id" => id}) do
    with {:ok, id} <- Request.path_id(id),
         {:ok, work_order} <- fetch_work_order(id),
         {:ok, _project} <-
           Target.project(
             conn.assigns.scope,
             work_order.workflow.project_id,
             {:project_users, :access_project}
           ) do
      render(conn, "show.json", work_order: work_order, conn: conn)
    end
  end

  defp fetch_work_order(id) do
    case WorkOrders.get(id, include: [:workflow, runs: []]) do
      nil -> {:error, :not_found}
      work_order -> {:ok, work_order}
    end
  end

  defp list(project_or_user, conn, params, filters) do
    page =
      WorkOrders.paginate_work_orders_for(
        project_or_user,
        filters,
        Filters.page(params)
      )

    render(conn, "index.json", page: page, filters: filters, conn: conn)
  end
end
