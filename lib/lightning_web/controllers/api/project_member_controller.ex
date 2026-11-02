defmodule LightningWeb.API.ProjectMemberController do
  @moduledoc """
  A project's members, each named by their user's id.

  `GET /api/projects/:project_id/members` is paged (`page`, `page_size`) and
  sorted by first name. Anyone who can open the project may list them.

  `PUT /api/projects/:project_id/members/:user_id` takes `role` (`admin`,
  `editor` or `viewer`, required) and `notify` (default `true`, applied only
  when the user is added). It adds the user, answering 201, or changes their
  role, answering 200; the same body again writes nothing. A user who doesn't
  exist is 404. A project has exactly one owner and this route doesn't move
  it, so making someone the owner, or changing the owner's role, is a
  `one_owner` entry at `#/role`. A new member the plan has no seat for is 402.

  `DELETE /api/projects/:project_id/members/:user_id` removes the member and
  revokes the project's access to the credentials they own, answering 204. A
  user who isn't a member is 404. The owner is a `one_owner` entry and, in a
  sandbox, an owner or admin of a project above it a `not_allowed` entry, both
  at the `user_id` path segment.

  `PUT /api/projects/:project_id/members/:user_id/notifications` takes
  `failure_alert` and `digest`, both required, and sets them together. Only
  the member themself may, on a person's own token; anyone else is 403.

  Adding and removing need `:add_project_user` and `:remove_project_user`
  (owners and admins).
  """
  use LightningWeb, :controller

  import Ecto.Changeset

  alias Lightning.Accounts
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectLimiter
  alias Lightning.Projects.ProjectUser
  alias Lightning.Projects.Sandboxes
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction,
       {:project_users, :access_project}
       when action == :index

  plug AuthorizeAction,
       {:project_users, :add_project_user}
       when action == :update

  plug AuthorizeAction,
       {:project_users, :remove_project_user}
       when action == :delete

  plug AuthorizeAction,
       {:project_users, :edit_failure_alerts}
       when action == :notifications

  @member_types %{role: ProjectUser.RolesEnum, notify: :boolean}
  @notification_types %{
    failure_alert: :boolean,
    digest: ProjectUser.DigestEnum
  }

  @one_owner {"would change who owns the project, which has exactly one owner",
              code: :one_owner}
  @owner_stays {"is the project's owner, who can't be removed", code: :one_owner}
  @parent_admin {"is an owner or admin of a project this sandbox is under",
                 code: :not_allowed}

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, params) do
    with {:ok, project} <- project(conn, :access_project) do
      render(conn, "index.json",
        page: Projects.paginate_project_users(project.id, Filters.page(params)),
        conn: conn
      )
    end
  end

  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, _params) do
    body = conn.body_params

    with {:ok, project} <- project(conn, :add_project_user),
         {:ok, user_id} <- Request.id(Request.param(conn, "user_id")),
         {:ok, user} <- fetch_user(user_id),
         :ok <- Request.check_object(body),
         membership = Projects.fetch_project_user(project.id, user.id),
         {:ok, request} <- member_request(body, membership) do
      put_member(conn, project, user, membership, request)
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def delete(conn, _params) do
    with {:ok, project} <- project(conn, :remove_project_user),
         {:ok, user_id} <- Request.id(Request.param(conn, "user_id")),
         {:ok, project_user} <- Projects.fetch_project_user(project.id, user_id),
         :ok <- removable(project, project_user) do
      Projects.delete_project_user!(project_user, conn.assigns.current_resource)
      send_resp(conn, :no_content, "")
    end
  end

  @spec notifications(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def notifications(conn, _params) do
    body = conn.body_params

    with {:ok, project} <- project(conn, :edit_failure_alerts),
         {:ok, user_id} <- Request.id(Request.param(conn, "user_id")),
         :ok <- own(conn, user_id),
         {:ok, project_user} <- Projects.fetch_project_user(project.id, user_id),
         :ok <- Request.check_object(body),
         {:ok, attrs} <- notification_request(body) do
      case Projects.set_notification_prefs(project_user, attrs) do
        :unchanged ->
          render_member(conn, project_user)

        {:ok, updated} ->
          render_member(conn, %{updated | user: project_user.user})

        {:error, _reason} = error ->
          error
      end
    end
  end

  defp project(conn, action) do
    Target.project(
      conn.assigns.scope,
      Request.param(conn, "project_id"),
      {:project_users, action}
    )
  end

  defp fetch_user(user_id) do
    case Accounts.get_user(user_id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  defp member_request(body, membership) do
    request =
      {%{notify: true}, @member_types}
      |> cast(body, Map.keys(@member_types))
      |> validate_required([:role, :notify])

    entries =
      Request.unknown_keys(body, [], Map.keys(@member_types)) ++
        Errors.from_changeset(request) ++
        owner_entries(get_field(request, :role), membership)

    with :ok <- Errors.refuse(entries), do: {:ok, apply_changes(request)}
  end

  defp owner_entries(:owner, _membership),
    do: [Errors.entry([:role], @one_owner)]

  defp owner_entries(role, {:ok, %ProjectUser{role: :owner}}) when role != nil,
    do: [Errors.entry([:role], @one_owner)]

  defp owner_entries(_role, _membership), do: []

  defp put_member(conn, _project, _user, {:ok, %{role: role} = member}, %{
         role: role
       }),
       do: render_member(conn, member)

  defp put_member(conn, project, _user, {:ok, member}, request) do
    with {:ok, _members} <-
           project
           |> Projects.add_project_users(
             [%{id: member.id, role: request.role}],
             conn.assigns.current_resource,
             false
           )
           |> Projects.unless_deleted(project),
         {:ok, member} <- changed(project, member) do
      render_member(conn, member)
    end
  end

  defp put_member(conn, project, user, {:error, :not_found}, request) do
    with :ok <- ProjectLimiter.request_new_user(project.id, 1),
         {:ok, _members} <-
           project
           |> Projects.add_project_users(
             [%{user_id: user.id, role: request.role}],
             conn.assigns.current_resource,
             request.notify
           )
           |> Projects.unless_deleted(project),
         {:ok, member} <- Projects.fetch_project_user(project.id, user.id) do
      conn |> put_status(:created) |> render_member(member)
    end
  end

  # A membership another request removed meanwhile is left out of the write
  # rather than refused, so it shows only when read back.
  defp changed(project, member) do
    case Projects.fetch_project_user(project.id, member.user_id) do
      {:ok, member} -> {:ok, member}
      {:error, :not_found} -> {:error, :concurrent_edit}
    end
  end

  defp removable(_project, %ProjectUser{role: :owner}),
    do: Errors.refuse([Errors.entry({:path, "user_id"}, @owner_stays)])

  defp removable(%Project{} = project, %ProjectUser{user: user}) do
    if Project.sandbox?(project) and Sandboxes.parent_admin?(project, user),
      do: Errors.refuse([Errors.entry({:path, "user_id"}, @parent_admin)]),
      else: :ok
  end

  # Decided on the id alone, so another member's row is refused whether or not
  # it exists.
  defp own(conn, user_id) do
    if user_id == conn.assigns.current_resource.id,
      do: :ok,
      else: {:error, :forbidden}
  end

  defp notification_request(body) do
    fields = Map.keys(@notification_types)

    request =
      {%{}, @notification_types}
      |> cast(body, fields)
      |> validate_required(fields)

    entries =
      Request.unknown_keys(body, [], fields) ++ Errors.from_changeset(request)

    with :ok <- Errors.refuse(entries), do: {:ok, apply_changes(request)}
  end

  defp render_member(conn, member),
    do: render(conn, "show.json", member: member, conn: conn)
end
