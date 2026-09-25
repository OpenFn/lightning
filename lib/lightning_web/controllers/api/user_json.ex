defmodule LightningWeb.API.UserJSON do
  @moduledoc false

  import LightningWeb.API.Helpers

  alias LightningWeb.Router.Helpers, as: Routes

  @fields ~w(email first_name last_name role)a

  def render("index.json", %{page: page, conn: conn}) do
    %{
      data: Enum.map(page.entries, &resource(conn, &1)),
      links: Map.merge(%{self: url_for(conn)}, pagination_links(conn, page))
    }
  end

  def render("show.json", %{user: user, conn: conn}) do
    %{data: resource(conn, user)}
  end

  defp resource(conn, user) do
    %{
      type: "users",
      id: user.id,
      attributes: Map.take(user, @fields),
      links: %{self: Routes.api_user_url(conn, :show, user)}
    }
  end
end
