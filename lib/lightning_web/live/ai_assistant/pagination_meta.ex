defmodule LightningWeb.Live.AiAssistant.PaginationMeta do
  @moduledoc """
  Pagination metadata for AI Assistant sessions.

  Provides pagination information to help with UI rendering and navigation.
  """

  defstruct [
    :current_page,
    :page_size,
    :total_count,
    :has_next_page,
    :has_prev_page
  ]

  @type t :: %__MODULE__{
          current_page: integer(),
          page_size: integer(),
          total_count: integer(),
          has_next_page: boolean(),
          has_prev_page: boolean()
        }

  @doc """
  Creates pagination metadata from current state.

  ## Parameters
    * current_sessions_count - Number of sessions currently loaded
    * page_size - Number of sessions per page
    * total_count - Total number of sessions available

  ## Returns
    * `%PaginationMeta{}` - Pagination metadata struct

  ## Examples
      # First page with 20 items loaded out of 100 total
      PaginationMeta.new(20, 20, 100)
      #=> %PaginationMeta{current_page: 1, page_size: 20, total_count: 100, has_next_page: true, has_prev_page: false}

      # Second page with 40 items loaded out of 100 total
      PaginationMeta.new(40, 20, 100)
      #=> %PaginationMeta{current_page: 2, page_size: 20, total_count: 100, has_next_page: true, has_prev_page: true}
  """
  def new(current_sessions_count, page_size, total_count) do
    # Calculate current page based on how many sessions we've loaded
    current_page = max(1, div(current_sessions_count - 1, page_size) + 1)

    # Check if there are more sessions to load
    has_next_page = current_sessions_count < total_count

    # Check if we're past the first page
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
  Returns the total number of pages.
  """
  def total_pages(%__MODULE__{total_count: total_count, page_size: page_size}) do
    max(1, div(total_count - 1, page_size) + 1)
  end

  @doc """
  Returns the current offset (for database queries).
  """
  def current_offset(%__MODULE__{
        current_page: current_page,
        page_size: page_size
      }) do
    (current_page - 1) * page_size
  end

  @doc """
  Returns a human-readable summary of the pagination state.

  ## Examples
      iex> meta = PaginationMeta.new(40, 20, 100)
      iex> PaginationMeta.summary(meta)
      "Showing 21-40 of 100"
  """
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
end
