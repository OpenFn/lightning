defmodule LightningWeb.AiAssistant.PaginationTest do
  use ExUnit.Case

  alias LightningWeb.Live.AiAssistant.PaginationMeta

  describe "new/3" do
    test "calculates first page correctly" do
      meta = PaginationMeta.new(20, 20, 100)

      assert meta.current_page == 1
      assert meta.has_next_page == true
      assert meta.has_prev_page == false
    end

    test "calculates middle page correctly" do
      meta = PaginationMeta.new(40, 20, 100)

      assert meta.current_page == 2
      assert meta.has_next_page == true
      assert meta.has_prev_page == true
    end

    test "handles empty dataset" do
      meta = PaginationMeta.new(0, 20, 0)

      assert meta.current_page == 1
      assert meta.has_next_page == false
      assert meta.has_prev_page == false
    end
  end

  describe "current_offset/1" do
    test "calculates correct offsets" do
      meta1 = PaginationMeta.new(20, 20, 100)
      assert PaginationMeta.current_offset(meta1) == 0

      meta2 = PaginationMeta.new(40, 20, 100)
      assert PaginationMeta.current_offset(meta2) == 20
    end
  end

  describe "summary/1" do
    test "formats summary correctly" do
      meta = PaginationMeta.new(40, 20, 100)
      assert PaginationMeta.summary(meta) == "Showing 21-40 of 100"
    end

    test "handles empty state" do
      meta = PaginationMeta.new(0, 20, 0)
      assert PaginationMeta.summary(meta) == "No items"
    end
  end

  describe "for_page/2" do
    test "calculates metadata for specific page" do
      current_meta = PaginationMeta.new(20, 20, 100)
      page3_meta = PaginationMeta.for_page(current_meta, 3)

      assert page3_meta.current_page == 3
      assert page3_meta.page_size == 20
      assert page3_meta.total_count == 100
      assert page3_meta.has_prev_page == true
      assert page3_meta.has_next_page == true
    end
  end

  describe "first_page?/1" do
    test "detects first page" do
      meta = PaginationMeta.new(20, 20, 100)
      assert PaginationMeta.first_page?(meta) == true

      meta2 = PaginationMeta.new(40, 20, 100)
      assert PaginationMeta.first_page?(meta2) == false
    end
  end

  describe "last_page?/1" do
    test "detects last page" do
      meta = PaginationMeta.new(100, 20, 100)
      assert PaginationMeta.last_page?(meta) == true

      meta2 = PaginationMeta.new(40, 20, 100)
      assert PaginationMeta.last_page?(meta2) == false
    end
  end

  describe "page_range/2" do
    test "returns all pages when total <= max_pages" do
      # 5 total pages
      meta = PaginationMeta.new(40, 20, 100)
      range = PaginationMeta.page_range(meta, 5)

      assert range == [1, 2, 3, 4, 5]
    end

    test "centers around current page when total > max_pages" do
      # Page 6 of 10
      meta = PaginationMeta.new(120, 20, 200)
      range = PaginationMeta.page_range(meta, 5)

      assert range == [4, 5, 6, 7, 8]
    end

    test "adjusts range at boundaries" do
      # Page 1 of 10
      meta = PaginationMeta.new(20, 20, 200)
      range = PaginationMeta.page_range(meta, 5)

      assert range == [1, 2, 3, 4, 5]

      # Page 10 of 10
      meta2 = PaginationMeta.new(200, 20, 200)
      range2 = PaginationMeta.page_range(meta2, 5)

      assert range2 == [6, 7, 8, 9, 10]
    end
  end
end
