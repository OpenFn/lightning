defmodule LightningWeb.API.OrganizationMemberController do
  @moduledoc """
  An organization's members, each named by their user's id.

  `GET /api/organizations/:organization_id/members` is paged and sorted by
  first name. Anyone in the organization may list them.

  `POST /api/organizations/:organization_id/members` takes `email` and `role`
  (`admin` or `member`), both required, and adds the user who has that email,
  answering 201. It gives them no access to the organization's projects. An
  email with no user is a `not_found` entry at `#/email`, and one already in
  the organization a `taken` entry.

  `PATCH /api/organizations/:organization_id/members/:user_id` takes `role`
  and answers 200; the same role again writes nothing.
  `DELETE /api/organizations/:organization_id/members/:user_id` takes them out
  of the organization, leaving their account and project memberships alone,
  and answers 204. A user who isn't a member is 404. Either is refused with a
  `one_admin` entry when it would leave the organization with no admin, at
  `#/role` or the `user_id` path segment. A member another request removes
  meanwhile is 409 `concurrent_edit`.

  Adding, re-roling and removing need an admin of the organization, as
  renaming it does.
  """
  use LightningWeb, :controller

  import Ecto.Changeset

  alias Lightning.Accounts
  alias Lightning.Organizations
  alias Lightning.Organizations.OrganizationUser
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction,
       {:organizations, :read_organization}
       when action == :index

  plug AuthorizeAction,
       {:organizations, :manage_organization}
       when action in [:create, :update, :delete]

  @role Ecto.ParameterizedType.init(Ecto.Enum, values: OrganizationUser.roles())
  @create_types %{email: :string, role: @role}
  @update_types %{role: @role}

  @no_admin_left {"would leave the organization with no admin", code: :one_admin}

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, params) do
    with {:ok, organization} <- organization(conn, :read_organization) do
      render(conn, "index.json",
        page:
          Organizations.paginate_members(organization.id, Filters.page(params)),
        conn: conn
      )
    end
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def create(conn, _params) do
    body = conn.body_params

    with {:ok, organization} <- organization(conn, :manage_organization),
         :ok <- Request.check_object(body),
         {:ok, request} <- parse(body, @create_types),
         {:ok, user} <- user_by_email(request.email),
         {:ok, member} <-
           organization
           |> Organizations.add_member(
             user,
             request.role,
             conn.assigns.current_resource
           )
           |> taken() do
      conn |> put_status(:created) |> render_member(member)
    end
  end

  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, _params) do
    body = conn.body_params

    with {:ok, member} <- member(conn),
         :ok <- Request.check_object(body),
         {:ok, request} <- parse(body, @update_types),
         {:ok, member} <-
           member
           |> Organizations.change_role(
             request.role,
             conn.assigns.current_resource
           )
           |> one_admin([:role]) do
      render_member(conn, member)
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def delete(conn, _params) do
    with {:ok, member} <- member(conn),
         {:ok, _removed} <-
           member
           |> Organizations.remove_member(conn.assigns.current_resource)
           |> one_admin({:path, "user_id"}) do
      send_resp(conn, :no_content, "")
    end
  end

  defp organization(conn, action) do
    actor = conn.assigns.current_resource

    Target.record(
      conn.assigns.scope,
      Request.param(conn, "organization_id"),
      {:organizations, action},
      &Organizations.fetch_organization(&1, actor)
    )
  end

  defp member(conn) do
    with {:ok, organization} <- organization(conn, :manage_organization),
         {:ok, user_id} <- Request.id(Request.param(conn, "user_id")) do
      Organizations.fetch_member(organization.id, user_id)
    end
  end

  defp parse(body, types) do
    fields = Map.keys(types)

    request =
      {%{}, types}
      |> cast(body, fields)
      |> validate_required(fields)

    entries =
      Request.unknown_keys(body, [], fields) ++ Errors.from_changeset(request)

    with :ok <- Errors.refuse(entries), do: {:ok, apply_changes(request)}
  end

  defp user_by_email(email) do
    case Accounts.get_user_by_email(email) do
      nil -> Errors.refuse([Errors.entry([:email], Errors.not_visible())])
      user -> {:ok, user}
    end
  end

  defp taken({:error, %Ecto.Changeset{}}),
    do:
      Errors.refuse([
        Errors.entry(
          [:email],
          {"is already a member of the organization", code: :taken}
        )
      ])

  defp taken(result), do: result

  defp one_admin({:error, :one_admin}, location),
    do: Errors.refuse([Errors.entry(location, @no_admin_left)])

  defp one_admin(result, _location), do: result

  defp render_member(conn, member),
    do: render(conn, "show.json", member: member, conn: conn)
end
