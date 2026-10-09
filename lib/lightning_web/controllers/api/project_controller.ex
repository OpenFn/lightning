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

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Policies.Provisioning
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.ServiceAccount

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

    with :ok <- known_keys(conn.body_params),
         {:ok, attrs} <- parse_body(conn.body_params, id) do
      case Projects.get_project(attrs.id) do
        nil -> create(conn, attrs, actor)
        project -> replace(conn, project, attrs, actor)
      end
    else
      {:error, :unknown_keys, keys} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: Map.new(keys, &{&1, ["is not accepted"]})})

      error ->
        error
    end
  end

  @body_types %{
    id: :binary_id,
    name: :string,
    description: :string,
    members: {:array, :map},
    notify: :boolean
  }

  @body_keys @body_types |> Map.keys() |> Enum.map(&to_string/1)

  defp known_keys(%{"_json" => _not_an_object}), do: :ok

  defp known_keys(body) do
    case Map.keys(body) -- @body_keys do
      [] -> :ok
      keys -> {:error, :unknown_keys, keys}
    end
  end

  defp parse_body(%{"_json" => _not_an_object}, _id) do
    {:error,
     {%{}, %{body: :map}}
     |> change()
     |> add_error(:body, "must be a JSON object")}
  end

  defp parse_body(body, id) do
    changeset =
      {%{notify: true}, @body_types}
      |> cast(body, Map.keys(@body_types))

    changeset =
      case Ecto.UUID.cast(id) do
        {:ok, id} ->
          changeset
          |> validate_change(:id, fn :id, body_id ->
            if body_id == id,
              do: [],
              else: [id: "does not match the id in the path"]
          end)
          |> put_change(:id, id)

        :error ->
          add_error(changeset, :id, "is not a UUID")
      end

    apply_action(changeset, :validate)
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
  defp authorize(
         _action,
         %ServiceAccount{},
         %Project{scheduled_deletion: %DateTime{}}
       ),
       do: {:error, :scheduled_for_deletion}

  defp authorize(action, actor, project) do
    if Permissions.can?(ProjectUsers, action, actor, project),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp create(conn, attrs, actor) do
    with true <- Provisioning.authorize(:create_project, actor, nil),
         {:ok, project_users} <- resolve_members(attrs[:members] || []) do
      attrs
      |> Map.take([:id, :name, :description])
      |> Map.put(:project_users, project_users)
      |> Projects.create_project(actor, notify: attrs.notify)
      |> case do
        {:ok, project} ->
          conn |> put_status(:created) |> render_project(project)

        {:error, changeset} ->
          if id_taken?(changeset),
            do: replace(conn, Projects.get_project(attrs.id), attrs, actor),
            else: render_create_errors(conn, changeset)
      end
    end
  end

  @roles ~w(owner admin editor viewer)

  defp resolve_members(members) do
    Enum.reduce_while(members, {:ok, []}, fn member, {:ok, resolved} ->
      case resolve_member(member) do
        {:ok, %{user_id: user_id} = project_user} ->
          if Enum.any?(resolved, &(&1.user_id == user_id)),
            do:
              {:halt, members_error("names #{member["email"]} more than once")},
            else: {:cont, {:ok, [project_user | resolved]}}

        {:error, message} ->
          {:halt, members_error(message)}
      end
    end)
  end

  defp members_error(message) do
    {:error,
     {%{}, %{members: {:array, :map}}}
     |> change()
     |> add_error(:members, message)}
  end

  defp resolve_member(%{"email" => email, "role" => role})
       when is_binary(email) and role in @roles do
    case Accounts.get_user_by_email(email) do
      %User{id: user_id} -> {:ok, %{user_id: user_id, role: role}}
      nil -> {:error, "no user has the email #{email}"}
    end
  end

  defp resolve_member(_member),
    do:
      {:error,
       "each member needs an email and a role of #{Enum.join(@roles, ", ")}"}

  # Another request created the project between our lookup and our insert.
  defp id_taken?(changeset) do
    Enum.any?(changeset.errors, fn {field, {_message, opts}} ->
      field == :id and opts[:constraint] == :unique
    end)
  end

  # The project's changeset checks members as `owner` and `project_users`;
  # this API calls them `members`.
  defp render_create_errors(conn, changeset) do
    errors = LightningWeb.CoreComponents.translate_errors(changeset)

    {member_errors, errors} = Map.split(errors, [:owner, :project_users])

    errors =
      if member_errors == %{},
        do: errors,
        else:
          Map.put(
            errors,
            :members,
            member_errors |> Map.values() |> List.flatten()
          )

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end

  defp render_project(conn, project) do
    render(conn, "show.json",
      project: Lightning.Repo.preload(project, project_users: :user),
      conn: conn
    )
  end
end
