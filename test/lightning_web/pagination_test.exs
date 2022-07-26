defmodule LightningWeb.PaginationTest do
  use ExUnit.Case, async: true

  alias LightningWeb.Pagination

  test "raw_pagination_links/2" do
    assert Pagination.raw_pagination_links(%{
             total_pages: 25,
             page_number: 3
           }) == [
             {:previous, 2},
             {1, 1},
             {2, 2},
             {3, 3},
             {4, 4},
             {5, 5},
             {6, 6},
             {7, 7},
             {8, 8},
             {:ellipsis, :ellipsis},
             {25, 25},
             {:next, 4}
           ]
  end
end
