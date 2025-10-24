defmodule LightningWeb.API.ProjectController do
  @moduledoc """
  API controller for project management.

  Provides read access to projects for authenticated users and API tokens.
  Users can list projects they have access to and retrieve individual project details.

  ## Query Parameters (index)

  - `page` - Page number (default: 1)
  - `page_size` - Number of items per page (default: 10)

  ## Examples

      GET /api/projects?page=1&page_size=20
      GET /api/projects/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
  """
  use LightningWeb, :controller

  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects

  action_fallback LightningWeb.FallbackController

  @doc """
  Lists all projects accessible to the authenticated user.

  Returns a paginated list of projects that the current user or API token
  has access to.

  ## Parameters

  - `conn` - The Plug connection struct with the current resource assigned
  - `params` - Map of query parameters for pagination

  ## Returns

  - Renders JSON with paginated list of projects

  ## Examples

      GET /api/projects
      GET /api/projects?page=2&page_size=50
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    pagination_attrs = Map.take(params, ["page_size", "page"])

    page =
      Projects.projects_for_user_query(conn.assigns.current_resource)
      |> Lightning.Repo.paginate(pagination_attrs)

    render(conn, "index.json", page: page, conn: conn)
  end

  @doc """
  Retrieves a specific project by ID.

  Returns detailed information about a single project if the authenticated
  user has access to it.

  ## Parameters

  - `conn` - The Plug connection struct with the current resource assigned
  - `params` - Map containing:
    - `id` - Project UUID (required)

  ## Returns

  - `200 OK` with project JSON on success
  - `404 Not Found` if project doesn't exist
  - `403 Forbidden` if user lacks access to the project

  ## Examples

      GET /api/projects/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    with project <- Projects.get_project(id),
         :ok <-
           ProjectUsers
           |> Permissions.can(
             :access_project,
             conn.assigns.current_resource,
             project
           ) do
      render(conn, "show.json", project: project, conn: conn)
    end
  end
end
