defmodule LightningWeb.API.WorkOrdersJSON do
  @moduledoc false

  import LightningWeb.API.Helpers

  alias LightningWeb.Router.Helpers, as: Routes

  @fields ~w(state last_activity inserted_at updated_at)a

  def render("index.json", %{page: page, conn: conn}) do
    %{
      data: Enum.map(page.entries, &resource(conn, &1)),
      included: [],
      meta: %{
        total_entries: page.total_entries,
        total_pages: page.total_pages,
        page_number: page.page_number,
        page_size: page.page_size
      },
      links:
        %{
          self: url_for(conn)
        }
        |> Map.merge(pagination_links(conn, page))
    }
  end

  def render("show.json", %{work_order: work_order, conn: conn}) do
    %{
      data: resource(conn, work_order),
      included: [],
      links: %{
        self: url_for(conn)
      }
    }
  end

  defp resource(conn, work_order) do
    %{
      type: "work_orders",
      relationships: %{},
      links: %{self: Routes.api_work_orders_url(conn, :show, work_order)},
      id: work_order.id,
      attributes: Map.take(work_order, @fields)
    }
  end
end
