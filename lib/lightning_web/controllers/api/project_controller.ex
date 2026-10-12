defmodule LightningWeb.API.ProjectController do
  @moduledoc """
  API controller for project management.

  Provides read access to projects for authenticated users and API tokens.
  Users can list projects they have access to and retrieve individual project details.

  `PUT /api/projects/:id` creates the project under that id with its members,
  or replaces the name and description of the project that has it.

  ## Query Parameters (index)

  - `page` - Page number (default: 1)
  - `page_size` - Number of items per page (default: 10, at most 100)

  ## Examples

      GET /api/projects?page=1&page_size=20
      GET /api/projects/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d

  ## Sample curl requests

  List all projects:

  ```bash
  curl http://localhost:4000/api/projects \\
    -H "Authorization: Bearer $TOKEN"
  ```

  Get a single project:

  ```bash
  curl http://localhost:4000/api/projects/$PROJECT_ID \\
    -H "Authorization: Bearer $TOKEN"
  ```
  """
  use LightningWeb, :controller

  import Ecto.Changeset

  alias Lightning.Policies.Permissions
  alias Lightning.Projects
  alias Lightning.Scope
  alias LightningWeb.API.PutRequest
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback LightningWeb.FallbackController

  plug AuthorizeAction, {:project_users, :access_project} when action == :show
  plug AuthorizeAction, {:project_users, :edit_project} when action == :update

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
  - `403 Forbidden` if user lacks access to the project, or the token lacks
    `projects:write`
  - `409 Conflict` to a caller who may see the project, if it is scheduled for
    deletion

  ## Examples

      GET /api/projects/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    with {:ok, scope} <- Scope.fetch(conn.assigns.scope, id),
         :ok <-
           Permissions.permit(
             :project_users,
             :access_project,
             scope,
             scope.project
           ) do
      render_project(conn, scope.project)
    end
  end

  @doc """
  Creates the project under the path's id, or replaces the name and description
  of the one that has it.

  `members` and `notify` only apply when the project is created.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, %{"id" => id}) do
    with {:ok, target} <- update_target(conn, id),
         {:ok, attrs} <- parse(conn, id) do
      case target do
        :new -> create(conn, attrs)
        project -> replace(conn, project, attrs)
      end
    end
  end

  defp update_target(conn, id) do
    case Scope.fetch(conn.assigns.scope, id) do
      {:ok, scope} ->
        with :ok <-
               Permissions.permit(
                 :project_users,
                 :edit_project,
                 scope,
                 scope.project
               ),
             do: {:ok, scope.project}

      {:error, :no_such_project} ->
        with :ok <-
               Permissions.permit(
                 :provisioning,
                 :create_project,
                 conn.assigns.scope,
                 nil
               ),
             do: {:ok, :new}

      error ->
        error
    end
  end

  defp parse(conn, id) do
    case parse_body(conn.body_params, id) do
      {:ok, attrs} -> {:ok, attrs}
      {:error, :invalid, errors} -> PutRequest.render_errors(conn, errors)
    end
  end

  @body_types %{
    id: :binary_id,
    name: :string,
    description: :string,
    members: {:array, :map},
    notify: :boolean
  }

  defp parse_body(body, id) do
    with {:ok, changeset} <-
           PutRequest.changeset(body, id, {%{notify: true}, @body_types}) do
      changeset
      |> validate_required(:notify, message: "must be true or false")
      |> PutRequest.attrs()
    end
  end

  defp replace(conn, project, attrs) do
    with {:ok, project} <-
           Projects.update_project(
             project,
             %{name: attrs[:name], description: attrs[:description]},
             conn.assigns.current_resource
           ) do
      render_project(conn, project)
    end
  end

  defp create(conn, attrs) do
    actor = conn.assigns.current_resource

    case Projects.members_by_email(attrs[:members] || []) do
      {:ok, project_users} ->
        attrs
        |> Map.take([:id, :name, :description])
        |> Map.put(:project_users, project_users)
        |> Projects.create_project(actor, notify: attrs.notify)
        |> case do
          {:ok, project} ->
            conn |> put_status(:created) |> render_project(project)

          # Created by someone else since the lookup: ask about it as the
          # project it now is.
          {:error, changeset} ->
            if PutRequest.unique_error?(changeset, :id),
              do: update(conn, %{"id" => attrs.id}),
              else: render_create_errors(conn, changeset)
        end

      {:error, messages} ->
        PutRequest.render_errors(conn, %{members: messages})
    end
  end

  # The project's changeset checks members as `owner` and `project_users`;
  # this API calls them `members`.
  defp render_create_errors(conn, changeset) do
    errors = PutRequest.flat_errors(changeset)

    {member_errors, errors} = Map.split(errors, [:owner, :project_users])

    errors =
      if member_errors == %{},
        do: errors,
        else: Map.put(errors, :members, Enum.concat(Map.values(member_errors)))

    PutRequest.render_errors(conn, errors)
  end

  defp render_project(conn, project) do
    render(conn, "show.json",
      project: Lightning.Repo.preload(project, project_users: :user),
      conn: conn
    )
  end
end
