defmodule LightningWeb.API.ProjectController do
  @moduledoc """
  API controller for project management.

  Lists, shows, creates and replaces projects for authenticated users and API
  tokens.

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

  alias Lightning.Accounts
  alias Lightning.Policies.Permissions
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectUser
  alias Lightning.Scope
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.PutBody
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction,
       {:project_users, :access_project, fallback: FallbackController}
       when action in [:index, :show]

  plug AuthorizeAction,
       {:project_users, :edit_project, fallback: FallbackController}
       when action == :update

  @accepted [:id, :name, :description, :members, :notify]
  @request_types %{members: {:array, :map}, notify: :boolean}
  @member_types %{email: :string, role: ProjectUser.RolesEnum}

  # The project changeset reports member errors under `owner` and
  # `project_users`. This API calls them `members`.
  @renames %{owner: :members, project_users: :members}

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
  Shows a project to a caller who may access it.

  A project the caller isn't a member of answers 404 `not_found`, as if it
  didn't exist. A member who hasn't met its MFA requirement, or a token without
  `projects:write`, gets 403. A project scheduled for deletion answers 409
  `scheduled_for_deletion` to a caller who may see it.

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

  `members` and `notify` only apply when the project is created. A refused body
  answers one 422 with every error in it, the body's keys, its members and the
  project's own fields together (error-format spec §9.6).
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, %{"id" => id}) do
    body = conn.body_params

    with {:ok, id} <- PutBody.path_id(id),
         {:ok, target} <- update_target(conn, id),
         {:ok, body_entries} <- PutBody.check(body, id, @accepted) do
      request =
        {%{notify: true}, @request_types}
        |> cast(body, Map.keys(@request_types))
        |> validate_required(:notify)

      fields = %{name: body["name"], description: body["description"]}
      entries = body_entries ++ Errors.from_changeset(request)

      case target do
        :new -> create(conn, Map.put(fields, :id, id), request, entries)
        project -> replace(conn, project, fields, entries)
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
    end
  end

  defp replace(conn, project, fields, entries) do
    changeset = Project.changeset(project, fields)

    with :ok <-
           Errors.refuse(entries ++ Errors.from_changeset(changeset, @renames)),
         {:ok, project} <-
           Projects.update_project(
             project,
             fields,
             conn.assigns.current_resource
           ) do
      render_project(conn, project)
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, Errors.problem(changeset, @renames)}

      error ->
        error
    end
  end

  defp create(conn, fields, request, entries) do
    {member_entries, fields, changeset} =
      case members(request) do
        {:ok, project_users} ->
          fields = Map.put(fields, :project_users, project_users)
          {[], fields, Project.project_with_users_changeset(%Project{}, fields)}

        # Without its members a new project can't be checked for an owner, so
        # only its own fields are.
        {:error, member_entries} ->
          {member_entries, fields, Project.changeset(%Project{}, fields)}
      end

    with :ok <-
           Errors.refuse(
             entries ++
               member_entries ++ Errors.from_changeset(changeset, @renames)
           ) do
      insert(conn, fields, notify: get_field(request, :notify))
    end
  end

  # A members list of the wrong type is already among the request's entries.
  defp members(request) do
    if Keyword.has_key?(request.errors, :members),
      do: {:error, []},
      else: resolve_members(get_field(request, :members) || [])
  end

  defp insert(conn, attrs, opts) do
    case Projects.create_project(attrs, conn.assigns.current_resource, opts) do
      {:ok, project} ->
        conn |> put_status(:created) |> render_project(project)

      # Someone else created it since the lookup. Rerun the request so the
      # caller is checked against that project.
      {:error, changeset} ->
        if PutBody.id_taken?(changeset),
          do: update(conn, %{"id" => attrs.id}),
          else: {:error, Errors.problem(changeset, @renames)}
    end
  end

  # Resolves each member's email to its user. Errors point at the member's
  # position in the request, which the project changeset doesn't keep
  # (error-format spec §7 items 3 and 4).
  defp resolve_members(members) do
    changesets =
      Enum.map(members, fn member ->
        {%{}, @member_types}
        |> cast(member, Map.keys(@member_types))
        |> validate_required(Map.keys(@member_types))
      end)

    user_ids =
      for(
        %{valid?: true} = changeset <- changesets,
        do: get_field(changeset, :email)
      )
      |> Accounts.list_users_by_emails()
      |> Map.new(&{String.downcase(&1.email), &1.id})

    {project_users, entries, _firsts} =
      changesets
      |> Enum.with_index()
      |> Enum.reduce({[], [], %{}}, fn {changeset, index}, acc ->
        resolve_member(changeset, [:members, index], user_ids, acc)
      end)

    if entries == [],
      do: {:ok, Enum.reverse(project_users)},
      else: {:error, Enum.reverse(entries)}
  end

  defp resolve_member(%{valid?: false} = changeset, path, _user_ids, acc) do
    {project_users, entries, firsts} = acc

    member_entries =
      for {field, error} <- changeset.errors,
          do: Errors.entry(path ++ [field], error)

    {project_users, member_entries ++ entries, firsts}
  end

  defp resolve_member(changeset, path, user_ids, acc) do
    {project_users, entries, firsts} = acc

    refuse_email =
      &{project_users, [Errors.entry(path ++ [:email], &1) | entries], firsts}

    case Map.fetch(user_ids, String.downcase(get_field(changeset, :email))) do
      :error ->
        refuse_email.(Errors.not_visible())

      {:ok, user_id} when is_map_key(firsts, user_id) ->
        refuse_email.(
          {"names the same user as " <> Errors.pointer(firsts[user_id]),
           code: :duplicate}
        )

      {:ok, user_id} ->
        project_user = %{user_id: user_id, role: get_field(changeset, :role)}
        {[project_user | project_users], entries, Map.put(firsts, user_id, path)}
    end
  end

  defp render_project(conn, project) do
    render(conn, "show.json",
      project: Lightning.Repo.preload(project, project_users: :user),
      conn: conn
    )
  end
end
