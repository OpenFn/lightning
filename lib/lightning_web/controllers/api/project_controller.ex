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

  alias Lightning.Policies.ProjectUsers
  alias Lightning.Policies.Provisioning
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.Scope
  alias Lightning.ServiceAccount
  alias LightningWeb.API.PutRequest

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
  - `409 Conflict` to a service account, if the project is scheduled for deletion

  ## Examples

      GET /api/projects/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    with %Project{} = project <- Projects.get_project(id),
         :ok <-
           authorize(:access_project, conn.assigns.current_resource, project) do
      render_project(conn, project)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  Creates the project under the path's id, or replaces the name and description
  of the one that has it.

  `members` and `notify` only apply when the project is created.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, %{"id" => id}) do
    actor = conn.assigns.current_resource

    case parse_body(conn.body_params, id) do
      {:ok, attrs} ->
        case Projects.get_project(attrs.id) do
          nil -> create(conn, attrs, actor)
          project -> replace(conn, project, attrs, actor)
        end

      {:error, :invalid, errors} ->
        PutRequest.render_errors(conn, errors)
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

  defp replace(conn, project, attrs, actor) do
    with :ok <- authorize(:edit_project, actor, project),
         {:ok, project} <-
           Projects.update_project(
             project,
             %{name: attrs[:name], description: attrs[:description]},
             actor
           ) do
      render_project(conn, project)
    end
  end

  # A service account passes every project policy, so telling it the project
  # is scheduled for deletion leaks nothing; a person gets the policy's answer.
  defp authorize(action, actor, project) do
    case Scope.fetch(actor, project) do
      {:ok, scope} ->
        if ProjectUsers.permitted?(action, scope),
          do: :ok,
          else: {:error, :forbidden}

      {:error, :project_scheduled_for_deletion}
      when is_struct(actor, ServiceAccount) ->
        {:error, :scheduled_for_deletion}

      {:error, _reason} ->
        {:error, :forbidden}
    end
  end

  defp create(conn, attrs, actor) do
    with true <- Provisioning.authorize(:create_project, actor, nil),
         {:ok, project_users} <-
           Projects.members_by_email(attrs[:members] || []) do
      attrs
      |> Map.take([:id, :name, :description])
      |> Map.put(:project_users, project_users)
      |> Projects.create_project(actor, notify: attrs.notify)
      |> case do
        {:ok, project} ->
          conn |> put_status(:created) |> render_project(project)

        {:error, changeset} ->
          if PutRequest.unique_error?(changeset, :id),
            do: replace(conn, Projects.get_project(attrs.id), attrs, actor),
            else: render_create_errors(conn, changeset)
      end
    else
      {:error, messages} when is_list(messages) ->
        PutRequest.render_errors(conn, %{members: messages})

      error ->
        error
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
