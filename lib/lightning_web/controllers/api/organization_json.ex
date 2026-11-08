defmodule LightningWeb.API.OrganizationJSON do
  @moduledoc false

  import LightningWeb.API.Helpers

  alias LightningWeb.Router.Helpers, as: Routes

  def render("index.json", %{page: page, conn: conn}) do
    %{
      data: Enum.map(page.entries, &resource(conn, &1)),
      included: [],
      links: pagination_links(conn, page, %{})
    }
  end

  def render("show.json", %{organization: organization, conn: conn}) do
    %{
      data: resource(conn, organization),
      included: [],
      links: %{self: self_url(conn)}
    }
  end

  defp resource(conn, organization) do
    %{
      type: "organizations",
      id: organization.id,
      attributes: %{
        name: organization.name,
        role: organization.role,
        inserted_at: organization.inserted_at,
        updated_at: organization.updated_at
      },
      relationships: %{},
      links: %{
        self: Routes.url(conn) <> "/api/organizations/#{organization.id}"
      }
    }
  end
end
