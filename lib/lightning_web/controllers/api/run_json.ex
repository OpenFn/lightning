# defmodule LightningWeb.API.RunJSON do
#   @moduledoc false

#   import LightningWeb.API.Helpers

#   alias LightningWeb.Router.Helpers, as: Routes

#   @fields ~w(started_at finished_at log)a

#   def render("index.json", %{page: page, conn: conn}) do
#     %{
#       data: Enum.map(page.entries, &resource(conn, &1)),
#       included: [],
#       links:
#         %{
#           self: url_for(conn)
#         }
#         |> Map.merge(pagination_links(conn, page))
#     }
#   end

#   def render("show.json", %{run: run, conn: conn}) do
#     %{
#       data: resource(conn, run),
#       included: [],
#       links: %{
#         self: url_for(conn)
#       }
#     }
#   end

#   defp resource(conn, run) do
#     %{
#       type: "runs",
#       relationships: %{},
#       links: %{self: Routes.api_run_url(conn, :show, run)},
#       id: run.id,
#       attributes: Map.take(run, @fields)
#     }
#   end
# end
