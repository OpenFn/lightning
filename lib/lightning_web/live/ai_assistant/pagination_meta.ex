defmodule LightningWeb.Live.AiAssistant.PaginationMeta do
  @moduledoc """
  Comprehensive pagination metadata for AI Assistant session management.

  This module provides intelligent pagination support for AI Assistant sessions,
  handling the complexities of offset-based pagination, infinite scroll patterns,
  and "Load More" functionality commonly used in chat interfaces.
  """
  @type t :: %__MODULE__{
          current_page: pos_integer(),
          page_size: pos_integer(),
          total_count: non_neg_integer(),
          has_next_page: boolean(),
          has_prev_page: boolean()
        }

  defstruct [
    :current_page,
    :page_size,
    :total_count,
    :has_next_page,
    :has_prev_page
  ]

  @doc """
  Creates pagination metadata from current loading state and totals.

  This is the primary constructor for pagination metadata, designed to work with
  progressive loading patterns where sessions are loaded incrementally rather
  than all at once.

  ## Parameters

  - `current_sessions_count` - Number of sessions currently loaded in the UI
  - `page_size` - Number of sessions per page/batch
  - `total_count` - Total number of sessions available from the data source

  ## Page Calculation Logic

  The current page is calculated based on how many sessions have been loaded:
  - **Page 1**: 1 to page_size sessions loaded
  - **Page 2**: (page_size + 1) to (2 * page_size) sessions loaded
  - **Page N**: ((N-1) * page_size + 1) to (N * page_size) sessions loaded

  ## Navigation State Logic

  - **has_next_page**: `true` if `current_sessions_count < total_count`
  - **has_prev_page**: `true` if `current_sessions_count > page_size`

  ## Examples

      # First page - 20 sessions loaded out of 100 total
      PaginationMeta.new(20, 20, 100)
      # => %PaginationMeta{
      #   current_page: 1,
      #   page_size: 20,
      #   total_count: 100,
      #   has_next_page: true,
      #   has_prev_page: false
      # }

      # Second page - 40 sessions loaded out of 100 total
      PaginationMeta.new(40, 20, 100)
      # => %PaginationMeta{
      #   current_page: 2,
      #   page_size: 20,
      #   total_count: 100,
      #   has_next_page: true,
      #   has_prev_page: true
      # }

      # Last page - all 100 sessions loaded
      PaginationMeta.new(100, 20, 100)
      # => %PaginationMeta{
      #   current_page: 5,
      #   page_size: 20,
      #   total_count: 100,
      #   has_next_page: false,
      #   has_prev_page: true
      # }

      # Empty state - no sessions available
      PaginationMeta.new(0, 20, 0)
      # => %PaginationMeta{
      #   current_page: 1,
      #   page_size: 20,
      #   total_count: 0,
      #   has_next_page: false,
      #   has_prev_page: false
      # }
  """
  @spec new(non_neg_integer(), pos_integer(), non_neg_integer()) :: t()
  def new(current_sessions_count, page_size, total_count) do
    current_page = max(1, div(current_sessions_count - 1, page_size) + 1)
    has_next_page = current_sessions_count < total_count
    has_prev_page = current_sessions_count > page_size

    %__MODULE__{
      current_page: current_page,
      page_size: page_size,
      total_count: total_count,
      has_next_page: has_next_page,
      has_prev_page: has_prev_page
    }
  end

  @doc """
  Calculates the total number of pages in the complete dataset.

  Determines how many pages are needed to display all available sessions
  with the current page size. Useful for generating complete page navigation
  and progress indicators.

  ## Parameters

  - `meta` - PaginationMeta struct containing total_count and page_size

  ## Returns

  The total number of pages as a positive integer (minimum 1).

  ## Examples

      # 100 sessions with 20 per page = 5 pages
      meta = PaginationMeta.new(40, 20, 100)
      PaginationMeta.total_pages(meta)
      # => 5

      # 95 sessions with 20 per page = 5 pages (partial last page)
      meta = PaginationMeta.new(20, 20, 95)
      PaginationMeta.total_pages(meta)
      # => 5

      # 20 sessions with 20 per page = 1 page (exact fit)
      meta = PaginationMeta.new(20, 20, 20)
      PaginationMeta.total_pages(meta)
      # => 1

      # Empty dataset = 1 page (for consistency)
      meta = PaginationMeta.new(0, 20, 0)
      PaginationMeta.total_pages(meta)
      # => 1

  ## Usage Patterns

      # Generate complete page navigation
      for page <- 1..PaginationMeta.total_pages(meta) do
        render_page_number(page, page == meta.current_page)
      end

      # Show progress indicator
      "Page # {meta.current_page} of # {PaginationMeta.total_pages(meta)}"

      # Determine if pagination needed
      if PaginationMeta.total_pages(meta) > 1 do
        show_pagination_controls()
      end
  """
  @spec total_pages(t()) :: pos_integer()
  def total_pages(%__MODULE__{total_count: total_count, page_size: page_size}) do
    max(1, div(total_count - 1, page_size) + 1)
  end

  @doc """
  Calculates the database offset for the current page.

  Determines the starting position for database queries using LIMIT/OFFSET
  patterns. Essential for efficient pagination with large datasets.

  ## Parameters

  - `meta` - PaginationMeta struct containing current_page and page_size

  ## Returns

  The zero-based offset for database queries.

  ## Examples

      # First page (page 1) = offset 0
      meta = PaginationMeta.new(20, 20, 100)  # current_page: 1
      PaginationMeta.current_offset(meta)
      # => 0

      # Second page (page 2) = offset 20
      meta = PaginationMeta.new(40, 20, 100)  # current_page: 2
      PaginationMeta.current_offset(meta)
      # => 20

      # Third page (page 3) = offset 40
      meta = PaginationMeta.new(60, 20, 100)  # current_page: 3
      PaginationMeta.current_offset(meta)
      # => 40

  ## Database Query Integration

      # Use with Ecto queries
      offset = PaginationMeta.current_offset(meta)

      from(s in ChatSession,
        limit: ^meta.page_size,
        offset: ^offset,
        order_by: [desc: :updated_at]
      )

      # Use with AiAssistant functions
      AiAssistant.list_sessions(
        resource,
        :desc,
        offset: PaginationMeta.current_offset(meta),
        limit: meta.page_size
      )
  """
  @spec current_offset(t()) :: non_neg_integer()
  def current_offset(%__MODULE__{
        current_page: current_page,
        page_size: page_size
      }) do
    (current_page - 1) * page_size
  end

  @doc """
  Generates a human-readable summary of the current pagination state.

  Creates user-friendly text describing what portion of the total dataset
  is currently visible. Commonly used in pagination controls and progress
  indicators to help users understand their position in the data.

  ## Parameters

  - `meta` - PaginationMeta struct with current pagination state

  ## Returns

  A string describing the visible range and total count.

  ## Examples

      # First page showing 20 of 100 sessions
      meta = PaginationMeta.new(20, 20, 100)
      PaginationMeta.summary(meta)
      # => "Showing 1-20 of 100"

      # Second page showing next 20 of 100 sessions
      meta = PaginationMeta.new(40, 20, 100)
      PaginationMeta.summary(meta)
      # => "Showing 21-40 of 100"

      # Last page showing partial results
      meta = PaginationMeta.new(95, 20, 95)
      PaginationMeta.summary(meta)
      # => "Showing 81-95 of 95"

      # Single page with fewer items than page size
      meta = PaginationMeta.new(15, 20, 15)
      PaginationMeta.summary(meta)
      # => "Showing 1-15 of 15"

      # Empty dataset
      meta = PaginationMeta.new(0, 20, 0)
      PaginationMeta.summary(meta)
      # => "No items"
  """
  @spec summary(t()) :: String.t()
  def summary(%__MODULE__{
        current_page: current_page,
        page_size: page_size,
        total_count: total_count
      }) do
    start_item = (current_page - 1) * page_size + 1
    end_item = min(current_page * page_size, total_count)

    if total_count == 0 do
      "No items"
    else
      "Showing #{start_item}-#{end_item} of #{total_count}"
    end
  end

  @doc """
  Determines if the current pagination represents the first page.

  Useful for conditionally enabling/disabling "Previous" or "First" navigation
  buttons in UI components.

  ## Examples

      meta = PaginationMeta.new(20, 20, 100)
      PaginationMeta.first_page?(meta)
      # => true

      meta = PaginationMeta.new(40, 20, 100)
      PaginationMeta.first_page?(meta)
      # => false
  """
  @spec first_page?(t()) :: boolean()
  def first_page?(%__MODULE__{current_page: 1}), do: true
  def first_page?(%__MODULE__{}), do: false

  @doc """
  Determines if the current pagination represents the last page.

  Useful for conditionally enabling/disabling "Next" or "Last" navigation
  buttons in UI components.

  ## Examples

      meta = PaginationMeta.new(100, 20, 100)  # All sessions loaded
      PaginationMeta.last_page?(meta)
      # => true

      meta = PaginationMeta.new(40, 20, 100)   # More sessions available
      PaginationMeta.last_page?(meta)
      # => false
  """
  @spec last_page?(t()) :: boolean()
  def last_page?(%__MODULE__{has_next_page: false}), do: true
  def last_page?(%__MODULE__{}), do: false

  @doc """
  Calculates pagination metadata for a specific page number.

  Creates new pagination metadata as if the user had navigated to a specific
  page, useful for implementing direct page navigation or calculating states
  for different pages.

  ## Parameters

  - `meta` - Current PaginationMeta struct
  - `target_page` - The page number to calculate metadata for

  ## Examples

      current_meta = PaginationMeta.new(20, 20, 100)

      # Calculate metadata for page 3
      page3_meta = PaginationMeta.for_page(current_meta, 3)
      # => %PaginationMeta{current_page: 3, has_prev_page: true, ...}

      # Calculate offset for page 3
      PaginationMeta.current_offset(page3_meta)
      # => 40
  """
  @spec for_page(t(), pos_integer()) :: t()
  def for_page(
        %__MODULE__{page_size: page_size, total_count: total_count},
        target_page
      ) do
    sessions_for_page = target_page * page_size
    new(sessions_for_page, page_size, total_count)
  end

  @doc """
  Returns the range of page numbers for pagination navigation.

  Calculates a sensible range of page numbers to display in pagination
  controls, typically centering around the current page with a maximum
  number of visible pages.

  ## Parameters

  - `meta` - Current PaginationMeta struct
  - `max_pages` - Maximum number of page links to show (default: 5)

  ## Examples

      meta = PaginationMeta.new(60, 20, 200)  # Page 3 of 10
      PaginationMeta.page_range(meta, 5)
      # => [1, 2, 3, 4, 5]

      meta = PaginationMeta.new(120, 20, 200)  # Page 6 of 10
      PaginationMeta.page_range(meta, 5)
      # => [4, 5, 6, 7, 8]
  """
  @spec page_range(t(), pos_integer()) :: [pos_integer()]
  def page_range(%__MODULE__{} = meta, max_pages \\ 5) do
    total = total_pages(meta)
    current = meta.current_page

    if total <= max_pages do
      Enum.to_list(1..total)
    else
      half_range = div(max_pages, 2)
      start_page = max(1, current - half_range)
      end_page = min(total, start_page + max_pages - 1)

      start_page = max(1, end_page - max_pages + 1)

      Enum.to_list(start_page..end_page)
    end
  end
end
