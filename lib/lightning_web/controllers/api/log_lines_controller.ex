defmodule LightningWeb.API.LogLinesController do
  @moduledoc """
  API controller for managing log lines.

  ## Query Parameters

  - `page` - Page number (default: 1)
  - `page_size` - Number of items per page (default: 10, at most 100)
  - `timestamp_after` - Filter logs after this ISO8601 datetime
  - `timestamp_before` - Filter logs before this ISO8601 datetime
  - `project_id` - Filter by project UUID
  - `workflow_id` - Filter by workflow UUID
  - `job_id` - Filter by job UUID
  - `work_order_id` - Filter by work order UUID
  - `run_id` - Filter by run UUID
  - `level` - Filter by log level (success, always, info, warn, error, debug)

  ## Examples

      GET /api/log_lines?page=1&page_size=50
      GET /api/log_lines?timestamp_after=2024-01-01T00:00:00Z
      GET /api/log_lines?run_id=uuid&level=error
      GET /api/log_lines?project_id=uuid&timestamp_after=2024-01-01T00:00:00Z

  """
  use LightningWeb, :controller

  alias Lightning.Invocation
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters

  action_fallback FallbackController

  plug LightningWeb.Plugs.AuthorizeAction,
       {:project_users, :access_project}

  @doc """
  Lists the log lines of the projects the caller may access, narrowed by the
  query's filters. Every bad filter is reported in one 400 `invalid_parameter`
  (error-format spec §9.4).
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, params) do
    with {:ok, filters} <-
           params
           |> Filters.log_lines()
           |> Errors.refuse_parameters() do
      page =
        Invocation.paginate_log_lines_for(
          conn.assigns.current_resource,
          filters,
          Filters.page(params)
        )

      render(conn, "index.json", page: page, filters: filters, conn: conn)
    end
  end
end
