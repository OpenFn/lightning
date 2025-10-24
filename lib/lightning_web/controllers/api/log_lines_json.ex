defmodule LightningWeb.API.LogLinesJSON do
  @moduledoc false

  import LightningWeb.API.Helpers

  @fields ~w(source level message timestamp step_id run_id)a

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

  defp resource(_conn, log_line) do
    %{
      type: "log_lines",
      id: log_line.id,
      attributes: Map.take(log_line, @fields)
    }
  end
end
