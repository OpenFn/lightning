defmodule LightningWeb.API.ProjectJSON do
  @moduledoc false

  import LightningWeb.API.Helpers

  alias LightningWeb.Router.Helpers, as: Routes

  @fields ~w(name description)a

  def render("index.json", %{page: page, conn: conn}) do
    %{
      data: Enum.map(page.entries, &resource(conn, &1)),
      included: [],
      links:
        %{
          self: url_for(conn)
        }
        |> Map.merge(pagination_links(conn, page))
    }
  end

  def render("show.json", %{project: project, conn: conn}) do
    %{
      data:
        put_in(
          resource(conn, project),
          [:attributes, :members],
          members(project)
        ),
      included: [],
      links: %{
        self: url_for(conn)
      }
    }
  end

  defp members(project) do
    Enum.map(project.project_users, &%{email: &1.user.email, role: &1.role})
  end

  defp resource(conn, project) do
    %{
      type: "projects",
      relationships: %{},
      links: %{self: Routes.api_project_url(conn, :show, project)},
      id: project.id,
      attributes: Map.take(project, @fields)
    }
  end
end
