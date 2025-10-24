defmodule LightningWeb.API.LogLinesController do
  @moduledoc """
  API controller for managing log lines.

  ## Query Parameters

  - `page` - Page number (default: 1)
  - `page_size` - Number of items per page (default: 10)
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

  action_fallback LightningWeb.FallbackController

  @doc """
  Lists log lines with pagination and filtering.

  Returns a paginated list of log lines filtered by the query parameters.
  Validates datetime parameters before applying filters and enforces
  authorization based on the current resource (user or API token).

  ## Parameters

  - `conn` - The Plug connection struct with the current resource assigned
  - `params` - Map of query parameters for filtering and pagination

  ## Returns

  - Renders JSON with paginated log lines on success
  - Returns error via fallback controller if datetime validation fails
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    with :ok <-
           Invocation.Query.validate_datetime_params(params, [
             "timestamp_after",
             "timestamp_before"
           ]) do
      pagination_attrs = Map.take(params, ["page_size", "page"])

      page =
        Invocation.Query.log_lines_for(conn.assigns.current_resource)
        |> Invocation.Query.filter_log_lines(params)
        |> Lightning.Repo.paginate(pagination_attrs)

      render(conn, "index.json", page: page, conn: conn)
    end
  end
end
