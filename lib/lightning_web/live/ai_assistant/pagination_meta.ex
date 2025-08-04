defmodule LightningWeb.Live.AiAssistant.PaginationMeta do
  @moduledoc """
  Pagination metadata for AI Assistant sessions.

  Handles offset-based pagination and infinite scroll patterns.
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
  Creates pagination metadata from current state.

  ## Examples

      iex> new(25, 20, 100)
      %PaginationMeta{current_page: 2, page_size: 20, total_count: 100, has_next_page: true, has_prev_page: true}

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
  Calculates total number of pages.
  """
  @spec total_pages(t()) :: pos_integer()
  def total_pages(%__MODULE__{total_count: total_count, page_size: page_size}) do
    max(1, div(total_count - 1, page_size) + 1)
  end

  @doc """
  Calculates database offset for current page.
  """
  @spec current_offset(t()) :: non_neg_integer()
  def current_offset(%__MODULE__{
        current_page: current_page,
        page_size: page_size
      }) do
    (current_page - 1) * page_size
  end

  @doc """
  Generates human-readable pagination summary.

  ## Examples

      iex> summary(%PaginationMeta{current_page: 2, page_size: 20, total_count: 45})
      "Showing 21-40 of 45"

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
  Checks if on first page.
  """
  @spec first_page?(t()) :: boolean()
  def first_page?(%__MODULE__{current_page: 1}), do: true
  def first_page?(%__MODULE__{}), do: false

  @doc """
  Checks if on last page.
  """
  @spec last_page?(t()) :: boolean()
  def last_page?(%__MODULE__{has_next_page: false}), do: true
  def last_page?(%__MODULE__{}), do: false

  @doc """
  Creates metadata for a specific page.
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
  Returns page numbers for navigation display.

  Centers around current page with max visible pages.
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
