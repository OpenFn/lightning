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
  """
  @spec first_page?(t()) :: boolean()
  def first_page?(%__MODULE__{current_page: 1}), do: true
  def first_page?(%__MODULE__{}), do: false

  @doc """
  Determines if the current pagination represents the last page.

  Useful for conditionally enabling/disabling "Next" or "Last" navigation
  buttons in UI components.
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
