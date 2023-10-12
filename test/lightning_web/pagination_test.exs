defmodule LightningWeb.PaginationTest do
  use ExUnit.Case, async: true

  alias LightningWeb.Pagination

  import Phoenix.LiveViewTest

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

  describe "page_link" do
    test "returns a link to previous" do
      assert previous =
               render_component(&LightningWeb.Pagination.page_link/1,
                 page_number: 1,
                 kind: :previous,
                 current_page: 2,
                 url: fn page: 1 -> "/page1" end
               )

      assert previous =~ "Previous"
      assert previous =~ "rounded-l-md"
    end

    test "returns a link to next" do
      assert next =
               render_component(&LightningWeb.Pagination.page_link/1,
                 page_number: 2,
                 kind: :next,
                 current_page: 1,
                 url: fn page: 2 -> "/page2" end
               )

      assert next =~ "Next"
      assert next =~ "rounded-r-md"
    end
  end
end
