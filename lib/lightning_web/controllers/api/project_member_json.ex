defmodule LightningWeb.API.ProjectMemberJSON do
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

  def render("show.json", %{member: project_user, conn: conn}) do
    %{
      data: member(conn, project_user),
      included: [],
      links: %{self: self_url(conn)}
    }
  end

  # A member is named by their user's id, so a client can address them without
  # knowing the membership row.
  defp member(conn, project_user) do
    %{
      type: "project_members",
      id: project_user.user_id,
      attributes: %{
        email: project_user.user.email,
        first_name: project_user.user.first_name,
        last_name: project_user.user.last_name,
        role: project_user.role,
        failure_alert: project_user.failure_alert,
        digest: project_user.digest
      },
      relationships: %{},
      links: %{
        self:
          Routes.url(conn) <>
            "/api/projects/#{project_user.project_id}/members/#{project_user.user_id}"
      }
    }
  end
end
