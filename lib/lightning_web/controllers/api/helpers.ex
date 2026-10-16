defmodule LightningWeb.API.Helpers do
  @moduledoc """
  Helpers for the API views
  """
  alias LightningWeb.Router.Helpers, as: Routes

  @doc """
  The page's links, each carrying the page size Scrivener applied rather than
  the one the request asked for.
  """
  def pagination_links(conn, page) do
    %{
      first: page_url(conn, page, 1),
      last: page_url(conn, page, page.total_pages),
      next:
        if(page.page_number < page.total_pages,
          do: page_url(conn, page, page.page_number + 1)
        ),
      prev:
        if(page.page_number > 1,
          do: page_url(conn, page, page.page_number - 1)
        )
    }
  end

  defp page_url(conn, page, number),
    do: url_for(conn, %{"page" => number, "page_size" => page.page_size})

  def url_for(conn, params \\ %{}) do
    %URI{
      URI.new!(Routes.url(conn) <> conn.request_path)
      | query: conn.query_params |> Map.merge(params) |> Plug.Conn.Query.encode()
    }
    |> URI.to_string()
  end
end
