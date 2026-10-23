defmodule LightningWeb.API.Helpers do
  @moduledoc """
  Helpers for the API views
  """
  alias LightningWeb.Router.Helpers, as: Routes

  @doc """
  The page's links, `self` included, carrying the filters the controller
  applied, as cast, and the page and page size Scrivener applied, and nothing
  else from the request (error-format spec §15 row 52). A filter the path
  already names, such as a nested route's `project_id`, is left out.
  """
  def pagination_links(conn, page, filters) do
    query =
      filters
      |> Map.new(fn {key, value} ->
        {Atom.to_string(key), query_value(value)}
      end)
      |> Map.drop(Map.keys(conn.path_params))

    %{
      self: page_url(conn, query, page, page.page_number),
      first: page_url(conn, query, page, 1),
      last: page_url(conn, query, page, page.total_pages),
      next:
        if(page.page_number < page.total_pages,
          do: page_url(conn, query, page, page.page_number + 1)
        ),
      prev:
        if(page.page_number > 1,
          do: page_url(conn, query, page, page.page_number - 1)
        )
    }
  end

  defp page_url(conn, query, page, number) do
    query
    |> Map.merge(%{"page" => number, "page_size" => page.page_size})
    |> url_with(conn)
  end

  defp query_value(%DateTime{} = at), do: DateTime.to_iso8601(at)
  defp query_value(values) when is_list(values), do: Enum.join(values, ",")
  defp query_value(value), do: value

  @doc """
  The request's URL without its query string, a single resource's `self`.
  """
  def self_url(conn), do: Routes.url(conn) <> conn.request_path

  defp url_with(query, conn) do
    %URI{
      URI.new!(self_url(conn))
      | query: Plug.Conn.Query.encode(query)
    }
    |> URI.to_string()
  end
end
