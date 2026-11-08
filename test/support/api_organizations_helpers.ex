defmodule LightningWeb.ApiOrganizationsHelpers do
  @moduledoc """
  Setup and expected bodies for the organization routes.
  """
  import Ecto.Query
  import Lightning.Factories

  alias Lightning.Repo

  @doc """
  An organization with `members`, a list of `{user, role}`.
  """
  def organization_with(members, attrs \\ []) do
    organization = insert(:organization, attrs)

    for {user, role} <- members,
        do:
          insert(:organization_user,
            organization: organization,
            user: user,
            role: role
          )

    organization
  end

  @doc "One organization as the routes show it, with the caller's `role`."
  def organization_json(organization, role) do
    url = LightningWeb.Endpoint.url() <> "/api/organizations/#{organization.id}"

    %{
      "type" => "organizations",
      "id" => organization.id,
      "attributes" => %{
        "name" => organization.name,
        "role" => role && to_string(role),
        "inserted_at" => DateTime.to_iso8601(organization.inserted_at),
        "updated_at" => DateTime.to_iso8601(organization.updated_at)
      },
      "relationships" => %{},
      "links" => %{"self" => url}
    }
  end

  @doc "The member path for `user_id` in `organization_id`."
  def org_member_path(organization_id, user_id),
    do: "/api/organizations/#{organization_id}/members/#{user_id}"

  @doc "One member as the routes show it."
  def org_member_json(organization_id, user, role, inserted_at) do
    %{
      "type" => "organization_members",
      "id" => user.id,
      "attributes" => %{
        "email" => user.email,
        "first_name" => user.first_name,
        "last_name" => user.last_name,
        "role" => to_string(role),
        "inserted_at" => DateTime.to_iso8601(inserted_at)
      },
      "relationships" => %{},
      "links" => %{
        "self" =>
          LightningWeb.Endpoint.url() <>
            org_member_path(organization_id, user.id)
      }
    }
  end

  @doc "The role of `user_id` in `organization_id`, or `nil`."
  def org_role_of(organization_id, user_id) do
    from(m in Lightning.Organizations.OrganizationUser,
      where: m.organization_id == ^organization_id and m.user_id == ^user_id,
      select: m.role
    )
    |> Repo.one()
  end

  @doc "When `user_id` joined `organization_id`."
  def joined_at(organization_id, user_id) do
    from(m in Lightning.Organizations.OrganizationUser,
      where: m.organization_id == ^organization_id and m.user_id == ^user_id,
      select: m.inserted_at
    )
    |> Repo.one!()
  end

  @doc "The organization's audit events, as `{event, actor_id, changes}`, sorted."
  def org_audit_events(organization_id) do
    from(a in Lightning.Auditing.Audit,
      where: a.item_type == "organization" and a.item_id == ^organization_id,
      select: {a.event, a.actor_id, a.changes}
    )
    |> Repo.all()
    |> Enum.map(fn {event, actor, changes} ->
      {event, actor, %{before: changes.before, after: changes.after}}
    end)
    |> Enum.sort()
  end
end
