defmodule LightningWeb.API.OrganizationController do
  @moduledoc """
  Organizations: the institutions above projects.

  `GET /api/organizations` is paged and sorted by name. It lists the
  organizations the caller belongs to, or every one on the instance for a
  superuser or the service account. `GET /api/organizations/:id` reads one.
  Each carries `role`, the caller's (`admin`, `member`, or `null`).

  `POST /api/organizations` takes `name` (required, at most 160 characters)
  and `members`, a list of `{"email", "role"}` objects whose `role` is `admin`
  or `member`, and answers 201. Only a superuser or the service account may
  create one. A superuser who doesn't list themselves joins as its admin. An
  email with no user is a `not_found` entry at `#/members/N/email`, a user
  listed twice is `duplicate`, and an organization with no admin is a
  `one_admin` entry at `#/members`.

  `PATCH /api/organizations/:id` takes `name` and answers 200. The same name
  again writes nothing.

  Reading needs a member of the organization; renaming an admin of it. A
  superuser or the service account may do either to any organization, and only
  they learn that an id names none (404) or isn't a UUID (400); anyone else
  hears 403 for both.
  """
  use LightningWeb, :controller

  import Ecto.Changeset

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Organizations
  alias Lightning.Organizations.OrganizationUser
  alias Lightning.Policies.Permissions
  alias Lightning.Scope
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction,
       {:organizations, :read_organization}
       when action in [:index, :show]

  plug AuthorizeAction,
       {:organizations, :create_organization}
       when action == :create

  plug AuthorizeAction,
       {:organizations, :manage_organization}
       when action == :update

  @member_types %{
    email: :string,
    role:
      Ecto.ParameterizedType.init(Ecto.Enum, values: OrganizationUser.roles())
  }
  @one_admin {"needs at least one admin", code: :one_admin}

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    scope = conn.assigns.scope

    page =
      Organizations.paginate_organizations(
        conn.assigns.current_resource,
        Filters.page(params),
        all: Scope.instance_wide?(scope)
      )

    render(conn, "index.json", page: page, conn: conn)
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(conn, _params) do
    with {:ok, organization} <- organization(conn, :read_organization) do
      render(conn, "show.json", organization: organization, conn: conn)
    end
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def create(conn, _params) do
    body = conn.body_params
    actor = conn.assigns.current_resource

    with :ok <-
           Permissions.permit(
             :organizations,
             :create_organization,
             conn.assigns.scope,
             nil
           ),
         :ok <- Request.check_object(body),
         {:ok, attrs, members} <- create_request(body, actor),
         {:ok, organization} <-
           Organizations.create_organization(attrs, members, actor) do
      conn
      |> put_status(:created)
      |> render("show.json", organization: organization, conn: conn)
    end
  end

  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, _params) do
    body = conn.body_params

    with {:ok, organization} <- organization(conn, :manage_organization),
         :ok <- Request.check_object(body),
         :ok <- update_request(body, organization),
         {:ok, organization} <-
           organization
           |> Organizations.update_organization(
             Map.take(body, ["name"]),
             conn.assigns.current_resource
           )
           |> refuse_changeset() do
      render(conn, "show.json", organization: organization, conn: conn)
    end
  end

  defp organization(conn, action) do
    actor = conn.assigns.current_resource

    Target.record(
      conn.assigns.scope,
      Request.param(conn, "id"),
      {:organizations, action},
      &Organizations.fetch_organization(&1, actor)
    )
  end

  defp update_request(body, organization) do
    changeset =
      organization
      |> Organizations.change_organization(Map.take(body, ["name"]))
      |> validate_required([:name])

    Errors.refuse(
      Request.unknown_keys(body, [], [:name]) ++
        required_name(body) ++ Errors.from_changeset(changeset)
    )
  end

  # Leaving `name` out of a PATCH changes nothing, but this route has nothing
  # else to change, so it's required.
  defp required_name(body) do
    if Map.has_key?(body, "name"),
      do: [],
      else: [Errors.entry([:name], {"can't be blank", code: :required})]
  end

  defp create_request(body, actor) do
    request =
      {%{members: []}, %{members: {:array, :map}}}
      |> cast(body, [:members])

    changeset =
      Organizations.change_organization(
        %Organizations.Organization{},
        Map.take(body, ["name"])
      )

    entries =
      Request.unknown_keys(body, [], [:name, :members]) ++
        Errors.from_changeset(changeset) ++ Errors.from_changeset(request)

    member_result =
      if request.valid?,
        do: resolve_members(get_field(request, :members)),
        else: {:error, []}

    case member_result do
      {:ok, members} ->
        members = with_creator(members, actor)

        admin_entries =
          if Enum.any?(members, &(&1.role == :admin)),
            do: [],
            else: [Errors.entry([:members], @one_admin)]

        with :ok <- Errors.refuse(entries ++ admin_entries),
             do: {:ok, %{name: get_field(changeset, :name)}, members}

      {:error, member_entries} ->
        Errors.refuse(entries ++ member_entries)
    end
  end

  # A superuser who creates an organization joins as its admin, unless they
  # listed themselves.
  defp with_creator(members, %User{id: id} = user) do
    if Enum.any?(members, &(&1.user.id == id)),
      do: members,
      else: members ++ [%{user: user, role: :admin}]
  end

  defp with_creator(members, _actor), do: members

  # Resolves each member's email to its user. Errors point at the member's
  # position in the request.
  defp resolve_members(members) do
    changesets =
      Enum.map(members, fn member ->
        {%{}, @member_types}
        |> cast(member, Map.keys(@member_types))
        |> validate_required(Map.keys(@member_types))
      end)

    users =
      for(%{valid?: true} = c <- changesets, do: get_field(c, :email))
      |> Accounts.list_users_by_emails()
      |> Map.new(&{String.downcase(&1.email), &1})

    {resolved, entries, _firsts} =
      changesets
      |> Enum.with_index()
      |> Enum.reduce({[], [], %{}}, fn {changeset, index}, acc ->
        resolve_member(changeset, [:members, index], users, acc)
      end)

    if entries == [],
      do: {:ok, Enum.reverse(resolved)},
      else: {:error, Enum.reverse(entries)}
  end

  defp resolve_member(%{valid?: false} = changeset, path, _users, acc) do
    {resolved, entries, firsts} = acc

    member_entries =
      for {field, error} <- changeset.errors,
          do: Errors.entry(path ++ [field], error)

    {resolved, member_entries ++ entries, firsts}
  end

  defp resolve_member(changeset, path, users, acc) do
    {resolved, entries, firsts} = acc

    refuse_email =
      &{resolved, [Errors.entry(path ++ [:email], &1) | entries], firsts}

    case Map.fetch(users, String.downcase(get_field(changeset, :email))) do
      :error ->
        refuse_email.(Errors.not_visible())

      {:ok, %User{id: id}} when is_map_key(firsts, id) ->
        refuse_email.(
          {"names the same user as " <> Errors.pointer(firsts[id]),
           code: :duplicate}
        )

      {:ok, user} ->
        member = %{user: user, role: get_field(changeset, :role)}
        {[member | resolved], entries, Map.put(firsts, user.id, path)}
    end
  end

  defp refuse_changeset({:error, %Ecto.Changeset{} = changeset}),
    do: {:error, Errors.problem(changeset)}

  defp refuse_changeset(result), do: result
end
