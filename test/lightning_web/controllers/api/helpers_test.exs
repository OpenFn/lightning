defmodule LightningWeb.API.HelpersTest do
  use ExUnit.Case, async: true

  alias LightningWeb.API.Helpers

  setup do
    conn =
      Plug.Test.conn(:get, "/api/runs")
      |> Plug.Conn.put_private(:phoenix_endpoint, LightningWeb.Endpoint)

    %{conn: conn}
  end

  @url "#{LightningWeb.Endpoint.url()}/api/runs"

  describe "pagination_links/3" do
    test "the first of several pages has no previous page", %{conn: conn} do
      assert links(conn, 1, 3) == %{
               self: "#{@url}?page=1&page_size=10",
               first: "#{@url}?page=1&page_size=10",
               last: "#{@url}?page=3&page_size=10",
               next: "#{@url}?page=2&page_size=10",
               prev: nil
             }
    end

    test "the last of several pages has no next page", %{conn: conn} do
      assert links(conn, 3, 3) == %{
               self: "#{@url}?page=3&page_size=10",
               first: "#{@url}?page=1&page_size=10",
               last: "#{@url}?page=3&page_size=10",
               next: nil,
               prev: "#{@url}?page=2&page_size=10"
             }
    end

    test "a single page has neither", %{conn: conn} do
      assert links(conn, 1, 1) == %{
               self: "#{@url}?page=1&page_size=10",
               first: "#{@url}?page=1&page_size=10",
               last: "#{@url}?page=1&page_size=10",
               next: nil,
               prev: nil
             }
    end

    test "carries the filters, as cast, except one the path already names", %{
      conn: conn
    } do
      conn = %{conn | path_params: %{"project_id" => "p1"}}

      filters = %{
        project_id: "p1",
        state: ["failed", "crashed"],
        inserted_after: ~U[2024-01-01 00:00:00.000000Z]
      }

      assert Helpers.pagination_links(conn, page(1, 1), filters).self ==
               "#{@url}?inserted_after=2024-01-01T00%3A00%3A00.000000Z&page=1&page_size=10&state=failed%2Ccrashed"
    end
  end

  defp links(conn, number, total_pages),
    do: Helpers.pagination_links(conn, page(number, total_pages), %{})

  defp page(number, total_pages),
    do: %Scrivener.Page{
      page_number: number,
      page_size: 10,
      total_pages: total_pages
    }
end
