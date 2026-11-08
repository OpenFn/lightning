defmodule Lightning.Organizations do
  @moduledoc """
  Organizations and their members.

  An organization is the institution above a set of projects. Every project
  belongs to one, and a person can belong to many, as an `:admin`, who manages
  the organization and its members, or a `:member`. Belonging to one gives no
  access to its projects: their members still decide that.

  An organization always keeps an admin. Changing a role or removing a member
  locks the organization's row first, so two admins demoting each other at
  once can't both succeed.

  Every write records an audit event on the organization, by the actor given.
  """
  import Ecto.Query

  alias Ecto.Multi
  alias Lightning.Accounts.User
  alias Lightning.Organizations.Audit
  alias Lightning.Organizations.Organization
  alias Lightning.Organizations.OrganizationUser
  alias Lightning.Repo

  @type actor :: Lightning.Actor.t()
  @type member :: %{user: User.t(), role: OrganizationUser.role()}

  @doc """
  A page of organizations sorted by name, each with `actor`'s role in it. With
  `all: true`, every organization on the instance; otherwise only those
  `actor` belongs to.
  """
  @spec paginate_organizations(actor(), map(), all: boolean()) ::
          Scrivener.Page.t()
  def paginate_organizations(actor, page, opts) do
    Organization
    |> with_role(actor, Keyword.fetch!(opts, :all))
    |> order_by([o], asc: o.name, asc: o.id)
    |> Repo.paginate(page)
  end

  @doc "The organization `id`, with `actor`'s role in it."
  @spec fetch_organization(Ecto.UUID.t(), actor()) ::
          {:ok, Organization.t()} | {:error, :not_found}
  def fetch_organization(id, actor) do
    Organization
    |> with_role(actor, true)
    |> where([o], o.id == ^id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      organization -> {:ok, organization}
    end
  end

  # A person's role comes from their membership; anyone else has none. Without
  # `all`, only organizations they belong to.
  defp with_role(query, %User{id: user_id}, all?) do
    query =
      from o in query,
        left_join: m in OrganizationUser,
        as: :membership,
        on: m.organization_id == o.id and m.user_id == ^user_id,
        select_merge: %{role: m.role}

    if all?,
      do: query,
      else: where(query, [membership: m], not is_nil(m.id))
  end

  defp with_role(query, _actor, true), do: query
  defp with_role(query, _actor, false), do: where(query, false)

  @doc "A changeset for an organization's name."
  @spec change_organization(Organization.t(), map()) :: Ecto.Changeset.t()
  def change_organization(%Organization{} = organization, attrs \\ %{}),
    do: Organization.changeset(organization, attrs)

  @doc """
  Creates an organization named in `attrs`, with `members`. Whoever calls it
  checks that one of them is an admin and that no user is listed twice.
  Answers the organization with `actor`'s role in it.
  """
  @spec create_organization(map(), [member()], actor()) ::
          {:ok, Organization.t()} | {:error, Ecto.Changeset.t()}
  def create_organization(attrs, members, actor) do
    Multi.new()
    |> Multi.insert(
      :organization,
      Organization.changeset(%Organization{}, attrs)
    )
    |> Multi.run(:audit_created, fn repo, %{organization: organization} ->
      "created"
      |> Audit.event(organization.id, actor, %{
        before: nil,
        after: %{"name" => organization.name}
      })
      |> repo.insert()
    end)
    |> then(fn multi ->
      Enum.reduce(members, multi, fn %{user: user, role: role}, multi ->
        Multi.run(multi, {:member, user.id}, fn repo, %{organization: o} ->
          insert_member(repo, o, user, role, actor)
        end)
      end)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{organization: organization}} ->
        fetch_organization(organization.id, actor)

      {:error, _step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Renames `organization`. The same name again writes nothing and records no
  audit event.
  """
  @spec update_organization(Organization.t(), map(), actor()) ::
          {:ok, Organization.t()} | {:error, Ecto.Changeset.t()}
  def update_organization(%Organization{} = organization, attrs, actor) do
    changeset = Organization.changeset(organization, attrs)

    case Audit.event("updated", organization.id, actor, changeset) do
      :no_changes ->
        if changeset.valid?,
          do: {:ok, organization},
          else: {:error, changeset}

      audit ->
        Multi.new()
        |> Multi.update(:organization, changeset)
        |> Multi.insert(:audit, audit)
        |> Repo.transaction()
        |> case do
          {:ok, %{organization: updated}} ->
            {:ok, %{updated | role: organization.role}}

          {:error, _step, changeset, _changes} ->
            {:error, changeset}
        end
    end
  end

  @doc "A page of `organization_id`'s members with their users, by first name."
  @spec paginate_members(Ecto.UUID.t(), map()) :: Scrivener.Page.t()
  def paginate_members(organization_id, page) do
    from(m in OrganizationUser,
      join: u in assoc(m, :user),
      where: m.organization_id == ^organization_id,
      order_by: [asc: u.first_name, asc: u.id],
      preload: [user: u]
    )
    |> Repo.paginate(page)
  end

  @doc "The membership of `user_id` in `organization_id`, with its user."
  @spec fetch_member(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, OrganizationUser.t()} | {:error, :not_found}
  def fetch_member(organization_id, user_id) do
    from(m in OrganizationUser,
      join: u in assoc(m, :user),
      where: m.organization_id == ^organization_id and m.user_id == ^user_id,
      preload: [user: u]
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      member -> {:ok, member}
    end
  end

  @doc """
  Adds `user` to `organization` with `role`. A user already in it is a
  changeset error on `:user_id`.
  """
  @spec add_member(Organization.t(), User.t(), OrganizationUser.role(), actor()) ::
          {:ok, OrganizationUser.t()} | {:error, Ecto.Changeset.t()}
  def add_member(%Organization{} = organization, %User{} = user, role, actor) do
    Repo.transaction(fn ->
      case insert_member(Repo, organization, user, role, actor) do
        {:ok, member} -> member
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp insert_member(repo, organization, user, role, actor) do
    with {:ok, member} <-
           %OrganizationUser{organization_id: organization.id}
           |> OrganizationUser.changeset(%{user_id: user.id, role: role})
           |> repo.insert(),
         {:ok, _audit} <-
           "member_added"
           |> Audit.event(organization.id, actor, %{
             before: nil,
             after: Audit.member_fields(%{user: user}, role)
           })
           |> repo.insert() do
      {:ok, %{member | user: user}}
    end
  end

  @doc """
  Changes `member`'s role. The same role again writes nothing. Answers
  `{:error, :one_admin}` when it would leave the organization with no admin,
  and `{:error, :concurrent_edit}` when another request removed the member
  meanwhile.
  """
  @spec change_role(OrganizationUser.t(), OrganizationUser.role(), actor()) ::
          {:ok, OrganizationUser.t()}
          | {:error, :one_admin | :concurrent_edit}
  def change_role(%OrganizationUser{role: role} = member, role, _actor),
    do: {:ok, member}

  def change_role(%OrganizationUser{} = member, role, actor) do
    in_locked_organization(member, fn current ->
      with :ok <- keeps_an_admin(current, role) do
        {1, _rows} =
          OrganizationUser
          |> where([m], m.id == ^current.id)
          |> Repo.update_all(set: [role: role, updated_at: now()])

        record_member_event(
          "member_role_changed",
          current,
          %{
            before: Audit.member_fields(member, current.role),
            after: Audit.member_fields(member, role)
          },
          actor
        )

        %{current | role: role, user: member.user}
      end
    end)
  end

  @doc """
  Takes `member` out of their organization. Their account and project
  memberships stay as they are. Answers `{:error, :one_admin}` for the last
  admin and `{:error, :concurrent_edit}` when another request removed them
  meanwhile.
  """
  @spec remove_member(OrganizationUser.t(), actor()) ::
          {:ok, OrganizationUser.t()}
          | {:error, :one_admin | :concurrent_edit}
  def remove_member(%OrganizationUser{} = member, actor) do
    in_locked_organization(member, fn current ->
      with :ok <- keeps_an_admin(current, nil) do
        Repo.delete!(current)

        record_member_event(
          "member_removed",
          current,
          %{before: Audit.member_fields(member, current.role), after: nil},
          actor
        )

        current
      end
    end)
  end

  # Locks the organization, then reads the membership again, so a check of
  # its admins sees every write that came first.
  defp in_locked_organization(%OrganizationUser{} = member, fun) do
    Repo.transaction(fn ->
      Organization
      |> where([o], o.id == ^member.organization_id)
      |> lock("FOR UPDATE")
      |> Repo.one!()

      case Repo.get(OrganizationUser, member.id) do
        nil ->
          Repo.rollback(:concurrent_edit)

        current ->
          case fun.(current) do
            {:error, reason} -> Repo.rollback(reason)
            result -> result
          end
      end
    end)
  end

  defp keeps_an_admin(%OrganizationUser{role: :admin} = member, new_role)
       when new_role != :admin do
    others =
      OrganizationUser
      |> where(
        [m],
        m.organization_id == ^member.organization_id and m.role == :admin and
          m.id != ^member.id
      )
      |> Repo.aggregate(:count)

    if others > 0, do: :ok, else: {:error, :one_admin}
  end

  defp keeps_an_admin(_member, _new_role), do: :ok

  defp record_member_event(event, member, changes, actor) do
    event
    |> Audit.event(member.organization_id, actor, changes)
    |> Repo.insert!()
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
