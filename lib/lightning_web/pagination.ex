defmodule LightningWeb.Pagination do
  @moduledoc """
  Pagination Components

  This has been extracted and adapted from `scrivener_html`.
  See: https://github.com/mgwidmann/scrivener_html
  """
  use LightningWeb, :component

  @raw_defaults [
    distance: 5,
    next: :next,
    previous: :previous,
    first: true,
    last: true,
    ellipsis: :ellipsis
  ]

  @doc """
  Returns the raw data in order to generate the proper HTML for pagination links. Data
  is returned in a `{text, page_number}` format where `text` is intended to be the text
  of the link and `page_number` is the page it should go to. Defaults are already supplied
  and they are as follows:
      #{inspect(@raw_defaults)}
  `distance` must be a positive non-zero integer or an exception is raised. `next` and `previous` should be
  strings but can be anything you want as long as it is truthy, falsey values will remove
  them from the output. `first` and `last` are only booleans, and they just include/remove
  their respective link from output. An example of the data returned:
      iex> Scrivener.HTML.raw_pagination_links(%{total_pages: 10, page_number: 5})
      [{"<<", 4}, {1, 1}, {2, 2}, {3, 3}, {4, 4}, {5, 5}, {6, 6}, {7, 7}, {8, 8}, {9, 9}, {10, 10}, {">>", 6}]
      iex> Scrivener.HTML.raw_pagination_links(%{total_pages: 20, page_number: 10}, first: ["←"], last: ["→"])
      [{"<<", 9}, {["←"], 1}, {:ellipsis, {:safe, "&hellip;"}}, {5, 5}, {6, 6},{7, 7}, {8, 8}, {9, 9}, {10, 10}, {11, 11}, {12, 12}, {13, 13}, {14, 14},{15, 15}, {:ellipsis, {:safe, "&hellip;"}}, {["→"], 20}, {">>", 11}]
  Simply loop and pattern match over each item and transform it to your custom HTML.
  """
  def raw_pagination_links(paginator, options \\ []) do
    options = Keyword.merge(@raw_defaults, options)

    add_first(paginator.page_number, options[:distance], options[:first])
    |> add_first_ellipsis(
      paginator.page_number,
      paginator.total_pages,
      options[:distance],
      options[:first]
    )
    |> add_previous(paginator.page_number)
    |> page_number_list(
      paginator.page_number,
      paginator.total_pages,
      options[:distance]
    )
    |> add_last_ellipsis(
      paginator.page_number,
      paginator.total_pages,
      options[:distance],
      options[:last]
    )
    |> add_last(
      paginator.page_number,
      paginator.total_pages,
      options[:distance],
      options[:last]
    )
    |> add_next(paginator.page_number, paginator.total_pages)
    |> Enum.map(fn
      :next ->
        if options[:next], do: {options[:next], paginator.page_number + 1}

      :previous ->
        if options[:previous],
          do: {options[:previous], paginator.page_number - 1}

      :first_ellipsis ->
        if options[:ellipsis] && options[:first],
          do: {:ellipsis, options[:ellipsis]}

      :last_ellipsis ->
        if options[:ellipsis] && options[:last],
          do: {:ellipsis, options[:ellipsis]}

      :first ->
        if options[:first], do: {options[:first], 1}

      :last ->
        if options[:last], do: {options[:last], paginator.total_pages}

      num when is_number(num) ->
        {num, num}
    end)
    |> Enum.filter(& &1)
  end

  attr :async_page, Phoenix.LiveView.AsyncResult, default: nil
  attr :page, :map, required: true
  attr :url, :any, required: true

  def pagination_bar(assigns) do
    ~H"""
    <div class="bg-white px-4 py-3 flex items-center justify-between border-t border-secondary-200 sm:px-6">
      <div>
        <%= if @async_page == Phoenix.LiveView.AsyncResult.loading() do %>
          <p class="text-sm text-secondary-700"></p>
        <% else %>
          <%= if @page.total_entries == 0 do %>
            <p class="text-sm text-secondary-700">No results found</p>
          <% else %>
            <p class="text-sm text-secondary-700">
              Showing
              <span class="font-medium">
                <%= @page.page_number * @page.page_size - @page.page_size + 1 %>
              </span>
              to
              <span class="font-medium">
                <%= min(@page.page_number * @page.page_size, @page.total_entries) %>
              </span>
              of <span class="font-medium"><%= @page.total_entries %></span>
              total results
            </p>
          <% end %>
        <% end %>
      </div>
      <nav
        class="relative z-0 inline-flex rounded-md shadow-sm -space-x-px"
        aria-label="Pagination"
      >
        <%= for {kind, page_number} <- LightningWeb.Pagination.raw_pagination_links(@page) do %>
          <LightningWeb.Pagination.page_link
            page_number={page_number}
            kind={kind}
            current_page={@page.page_number}
            url={@url}
          />
        <% end %>
      </nav>
    </div>
    """
  end

  def page_link(assigns) do
    case assigns.kind do
      :previous ->
        ~H"""
        <.link
          patch={assigns.url.(page: assigns.page_number)}
          class="relative inline-flex items-center px-2 py-2 rounded-l-md
          border border-secondary-300 bg-white text-sm font-medium
          text-secondary-500 hover:bg-secondary-50"
        >
          <span class="sr-only">Previous</span>
          <Icon.chevron_left />
        </.link>
        """

      :next ->
        ~H"""
        <.link
          patch={assigns.url.(page: assigns.page_number)}
          class="relative inline-flex items-center px-2 py-2 rounded-r-md
          border border-secondary-300 bg-white text-sm font-medium
          text-secondary-500 hover:bg-secondary-50"
        >
          <span class="sr-only">Next</span>
          <Icon.chevron_right />
        </.link>
        """

      :ellipsis ->
        ~H"""
        <div class="bg-white border-secondary-300 text-secondary-500
           relative inline-flex items-center px-4 py-2 border text-sm font-medium">
          &hellip;
        </div>
        """

      _ ->
        page_link_box(
          assign(assigns, active: assigns.current_page == assigns.page_number)
        )
    end
  end

  defp page_link_box(assigns) do
    patch_class =
      if assigns.active do
        "z-10 bg-primary-50 border-primary-500 text-primary-600 relative inline-flex items-center px-4 py-2 border text-sm font-medium"
      else
        "bg-white border-secondary-300 text-secondary-500 hover:bg-secondary-50 relative inline-flex items-center px-4 py-2 border text-sm font-medium"
      end

    assigns = assign(assigns, :patch_class, patch_class)

    ~H"""
    <.link patch={assigns.url.(page: assigns.page_number)} class={@patch_class}>
      <%= assigns.page_number %>
    </.link>
    """
  end

  # Computing page number ranges
  defp page_number_list(list, page, total, distance)
       when is_integer(distance) and distance >= 1 do
    list ++
      Enum.to_list(
        beginning_distance(page, total, distance)..end_distance(
          page,
          total,
          distance
        )
      )
  end

  defp page_number_list(_list, _page, _total, _distance) do
    raise "Scrivener.HTML: Distance cannot be less than one."
  end

  # Beginning distance computation
  # For low page numbers
  defp beginning_distance(page, _total, distance) when page - distance < 1 do
    page - (distance + (page - distance - 1))
  end

  # For medium to high end page numbers
  defp beginning_distance(page, total, distance) when page <= total do
    page - distance
  end

  # For page numbers over the total number of pages (prevent DOS attack generating too many pages)
  defp beginning_distance(page, total, distance) when page > total do
    total - distance
  end

  # End distance computation
  # For high end page numbers (prevent DOS attack generating too many pages)
  defp end_distance(page, total, distance)
       when page + distance >= total and total != 0 do
    total
  end

  # For when there is no pages, cannot trust page number because it is supplied by user potentially (prevent DOS attack)
  defp end_distance(_page, 0, _distance) do
    1
  end

  # For low to mid range page numbers (guard here to ensure crash if something goes wrong)
  defp end_distance(page, total, distance) when page + distance < total do
    page + distance
  end

  # Adding next/prev/first/last links
  defp add_previous(list, page) when page != 1 do
    [:previous | list]
  end

  defp add_previous(list, _page) do
    list
  end

  defp add_first(page, distance, true) when page - distance > 1 do
    [1]
  end

  defp add_first(page, distance, first)
       when page - distance > 1 and first != false do
    [:first]
  end

  defp add_first(_page, _distance, _included) do
    []
  end

  defp add_last(list, page, total, distance, true)
       when page + distance < total do
    list ++ [total]
  end

  defp add_last(list, page, total, distance, last)
       when page + distance < total and last != false do
    list ++ [:last]
  end

  defp add_last(list, _page, _total, _distance, _included) do
    list
  end

  defp add_next(list, page, total) when page != total and page < total do
    list ++ [:next]
  end

  defp add_next(list, _page, _total) do
    list
  end

  defp add_first_ellipsis(list, page, total, distance, true) do
    add_first_ellipsis(list, page, total, distance + 1, nil)
  end

  defp add_first_ellipsis(list, page, _total, distance, _first)
       when page - distance > 1 and page > 1 do
    list ++ [:first_ellipsis]
  end

  defp add_first_ellipsis(list, _page_number, _total, _distance, _first) do
    list
  end

  defp add_last_ellipsis(list, page, total, distance, true) do
    add_last_ellipsis(list, page, total, distance + 1, nil)
  end

  defp add_last_ellipsis(list, page, total, distance, _)
       when page + distance < total and page != total do
    list ++ [:last_ellipsis]
  end

  defp add_last_ellipsis(list, _page_number, _total, _distance, _last) do
    list
  end
end
