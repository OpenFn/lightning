defmodule LightningWeb.API.WorkOrdersController do
  @moduledoc """
  API controller for managing work orders.

  ## Query Parameters

  - `page` - Page number (default: 1)
  - `page_size` - Number of items per page (default: 10)
  - `inserted_after` - Filter work orders created after this ISO8601 datetime
  - `inserted_before` - Filter work orders created before this ISO8601 datetime
  - `updated_after` - Filter work orders updated after this ISO8601 datetime
  - `updated_before` - Filter work orders updated before this ISO8601 datetime

  ## Examples

      GET /api/work_orders?page=1&page_size=20
      GET /api/work_orders?inserted_after=2024-01-01T00:00:00Z
      GET /api/work_orders?inserted_after=2024-01-01T00:00:00Z&inserted_before=2024-12-31T23:59:59Z
      GET /api/projects/:project_id/work_orders?inserted_after=2024-01-01T00:00:00Z

  """
  use LightningWeb, :controller

  alias Lightning.Invocation
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.WorkOrders

  action_fallback LightningWeb.FallbackController

  def index(conn, %{"project_id" => project_id} = params) do
    pagination_attrs = Map.take(params, ["page_size", "page"])

    with :ok <-
           Invocation.Query.validate_datetime_params(params, [
             "inserted_after",
             "inserted_before",
             "updated_after",
             "updated_before"
           ]),
         project <- Lightning.Projects.get_project(project_id),
         :ok <-
           ProjectUsers
           |> Permissions.can(
             :access_project,
             conn.assigns.current_resource,
             project
           ) do
      page =
        WorkOrders.work_orders_for_project_query(project)
        |> Invocation.Query.filter_work_orders(params)
        |> Lightning.Repo.paginate(pagination_attrs)

      render(conn, "index.json", page: page, conn: conn)
    end
  end

  def index(conn, params) do
    with :ok <-
           Invocation.Query.validate_datetime_params(params, [
             "inserted_after",
             "inserted_before",
             "updated_after",
             "updated_before"
           ]) do
      pagination_attrs = Map.take(params, ["page_size", "page"])

      page =
        Invocation.Query.work_orders_for(conn.assigns.current_resource)
        |> Invocation.Query.filter_work_orders(params)
        |> Lightning.Repo.paginate(pagination_attrs)

      render(conn, "index.json", page: page, conn: conn)
    end
  end

  def show(conn, %{"id" => id}) do
    with work_order <-
           WorkOrders.get(id, include: [workflow: :project, runs: []]),
         :ok <-
           ProjectUsers
           |> Permissions.can(
             :access_project,
             conn.assigns.current_resource,
             work_order.workflow.project
           ) do
      render(conn, "show.json", work_order: work_order, conn: conn)
    end
  end
end
