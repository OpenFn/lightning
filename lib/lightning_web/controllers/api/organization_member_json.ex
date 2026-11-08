defmodule LightningWeb.API.OrganizationMemberJSON do
  @moduledoc false

  import LightningWeb.API.Helpers

  alias LightningWeb.Router.Helpers, as: Routes

  def render("index.json", %{page: page, conn: conn}) do
    %{
      data: Enum.map(page.entries, &member(conn, &1)),
      included: [],
      links: pagination_links(conn, page, %{})
    }
  end

  def render("show.json", %{member: member, conn: conn}) do
    %{
      data: member(conn, member),
      included: [],
      links: %{self: self_url(conn)}
    }
  end

  # A member is named by their user's id, as a project's members are.
  defp member(conn, member) do
    %{
      type: "organization_members",
      id: member.user_id,
      attributes: %{
        email: member.user.email,
        first_name: member.user.first_name,
        last_name: member.user.last_name,
        role: member.role,
        inserted_at: member.inserted_at
      },
      relationships: %{},
      links: %{
        self:
          Routes.url(conn) <>
            "/api/organizations/#{member.organization_id}/members/#{member.user_id}"
      }
    }
  end
end
