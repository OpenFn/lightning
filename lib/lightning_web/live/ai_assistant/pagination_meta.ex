defmodule LightningWeb.Live.AiAssistant.PaginationMeta do
  @moduledoc """
  Comprehensive pagination metadata for AI Assistant session management.

  This module provides intelligent pagination support for AI Assistant sessions,
  handling the complexities of offset-based pagination, infinite scroll patterns,
  and "Load More" functionality commonly used in chat interfaces.

  ## Pagination Patterns Supported

  ### Traditional Page-Based Navigation
  - **Page numbers** with prev/next navigation
  - **Page size control** for different viewing preferences
  - **Total page calculation** for complete navigation
  - **Current page tracking** for state management

  ### Infinite Scroll & Load More
  - **Progressive loading** of sessions as user scrolls
  - **Load more buttons** for explicit content expansion
  - **Has more detection** for enabling/disabling controls
  - **Offset calculation** for efficient database queries

  ### Chat Interface Optimization
  - **Recent-first ordering** typical in chat applications
  - **Session preview** with efficient message counting
  - **Responsive pagination** adapting to different screen sizes
  - **Performance optimization** for large session lists

  ## Key Features

  ### Intelligent Page Calculation
  - **Dynamic page detection** based on loaded item count
  - **Boundary handling** for edge cases (empty lists, partial pages)
  - **Flexible page sizing** supporting different UI requirements
  - **Accurate navigation state** for prev/next controls

  ### Database Query Integration
  - **Offset calculation** for LIMIT/OFFSET queries
  - **Efficient batch loading** minimizing database round trips
  - **Count optimization** with separate count queries when needed
  - **Performance-aware pagination** for large datasets

  ### User Experience Enhancement
  - **Loading state management** for progressive content
  - **Navigation feedback** with clear current position
  - **Accessibility support** with semantic pagination controls
  - **Mobile-friendly patterns** for touch interfaces

  ## Usage Patterns

  ### Basic Session Pagination
  ```elixir
  # Load first page of sessions
  %{sessions: sessions, pagination: meta} =
    AiAssistant.list_sessions(resource, :desc, offset: 0, limit: 20)

  # Meta provides: %PaginationMeta{current_page: 1, has_next_page: true, ...}
  ```

  ### Load More Implementation
  ```elixir
  # Check if more content available
  if meta.has_next_page do
    # Calculate next offset
    next_offset = meta.current_page * meta.page_size
    # Load next batch...
  end
  ```

  ### UI Navigation Integration
  ```elixir
  # Generate page navigation
  for page <- 1..PaginationMeta.total_pages(meta) do
    render_page_link(page, page == meta.current_page)
  end
  ```

  ## Implementation Philosophy

  The module follows a "progressive loading" philosophy where:
  - **Sessions load incrementally** as users explore conversation history
  - **Navigation state adapts** to the current loading progress
  - **Database queries optimize** for the most common access patterns
  - **UI components receive** all necessary state for intelligent rendering

  ## Performance Considerations

  - **Efficient calculations** using integer arithmetic for page math
  - **Minimal memory footprint** with simple struct design
  - **Database-friendly offsets** for optimal query performance
  - **Lazy evaluation** where calculations happen on-demand
  """

  @typedoc """
  Pagination metadata structure containing all information needed for navigation.

  ## Fields

  - `:current_page` - One-based page number indicating current position
  - `:page_size` - Number of items per page (consistent across pagination)
  - `:total_count` - Total number of items available across all pages
  - `:has_next_page` - Boolean indicating if more content is available to load
  - `:has_prev_page` - Boolean indicating if user can navigate to previous content

  ## Usage

  This struct is designed to be used with UI components for:
  - Enabling/disabling navigation buttons
  - Calculating database query offsets
  - Displaying progress information
  - Managing loading states
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

  ## Implementation Notes

  - Uses `max(1, ...)` to ensure page numbers start at 1
  - Handles edge cases like empty datasets gracefully
  - Optimized for incremental loading patterns
  - Compatible with standard database LIMIT/OFFSET patterns
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

  ## Implementation Notes

  - Uses ceiling division with `div(total - 1, size) + 1` pattern
  - Ensures minimum of 1 page even for empty datasets
  - Handles partial last pages correctly
  - O(1) constant time calculation
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

  ## Implementation Notes

  - Zero-based offset compatible with SQL OFFSET clause
  - Direct calculation without iteration for O(1) performance
  - Works with both forward and backward pagination
  - Consistent with database pagination standards
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

  ## UI Integration

      # In pagination footer
      <div class="pagination-info">
        <%= PaginationMeta.summary(@pagination) %>
      </div>

      # In accessible pagination controls
      <nav aria-label="Sessions pagination">
        <p><%= PaginationMeta.summary(@pagination) %></p>
        <!-- pagination buttons -->
      </nav>

      # In loading states
      <%= if @loading do %>
        Loading more sessions...
      <% else %>
        <%= PaginationMeta.summary(@pagination) %>
      <% end %>

  ## Accessibility Features

  - **Clear language** describing visible content range
  - **Total context** helping users understand dataset size
  - **Empty state handling** with appropriate messaging
  - **Screen reader friendly** text for assistive technologies

  ## Implementation Notes

  - Handles edge cases like empty datasets gracefully
  - Uses 1-based numbering for user-friendly display
  - Ensures end_item never exceeds total_count
  - Optimized string formatting for performance
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

  ## UI Usage

      <%= if not PaginationMeta.first_page?(@pagination) do %>
        <button phx-click="goto_first_page">First</button>
      <% end %>
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

  ## UI Usage

      <%= if not PaginationMeta.last_page?(@pagination) do %>
        <button phx-click="goto_last_page">Last</button>
      <% end %>
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

  ## Implementation Notes

  - Preserves page_size and total_count from original metadata
  - Recalculates navigation state for the target page
  - Useful for implementing "jump to page" functionality
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

  ## UI Usage

      <%= for page <- PaginationMeta.page_range(@pagination) do %>
        <button
          class={if page == @pagination.current_page, do: "active"}
          phx-click="goto_page"
          phx-value-page={page}
        >
          <%= page %>
        </button>
      <% end %>
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
