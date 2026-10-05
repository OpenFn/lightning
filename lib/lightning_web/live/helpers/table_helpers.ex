defmodule LightningWeb.Live.Helpers.TableHelpers do
  @moduledoc """
  Utilities for simplifying common table operations like sorting and filtering.

  This module provides reusable functions to reduce complexity in LiveView components
  that handle sortable, filterable tables.
  """

  use LightningWeb, :component

  @doc """
  Renders a filter input with magnifying glass icon and clear button.

  ## Attributes

  - `filter` - The current filter value
  - `placeholder` - Placeholder text for the input
  - `target` - Optional phx-target for the events
  - All other attributes are passed through to the input
  """
  attr :filter, :string, required: true
  attr :placeholder, :string, default: "Filter..."
  attr :target, :any, default: nil
  attr :rest, :global, include: ~w(class phx-keyup phx-debounce)

  def filter_input(assigns) do
    ~H"""
    <div class="mb-4">
      <div class="relative max-w-sm">
        <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
          <Heroicons.magnifying_glass class="h-5 w-5 text-gray-400" />
        </div>
        <.input
          type="text"
          name="filter"
          value={@filter}
          placeholder={@placeholder}
          class="block w-full rounded-md py-1.5 pl-10 pr-10 text-gray-900 placeholder:text-gray-400 focus:ring-inset focus:ring-indigo-600 sm:text-sm sm:leading-6"
          phx-keyup="filter"
          phx-debounce="300"
          phx-target={@target}
          {@rest}
        />
        <div class="absolute inset-y-0 right-0 flex items-center pr-3">
          <a
            href="#"
            class={if @filter == "", do: "hidden"}
            id="clear_filter_button"
            phx-click="clear_filter"
            phx-target={@target}
          >
            <Heroicons.x_mark class="h-5 w-5 text-gray-400" />
          </a>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Creates a sort function based on direction string.

  ## Examples

      iex> sort_compare_fn("asc")
      &<=/2

      iex> sort_compare_fn("desc")
      &>=/2
  """
  def sort_compare_fn("asc"), do: &<=/2
  def sort_compare_fn("desc"), do: &>=/2

  @doc """
  Resolves a client-supplied sort field to one of `allowed` (a list of column
  atoms), returning `default` for anything unrecognised.

  Matches on each allowed atom's string form rather than calling
  `String.to_atom/1` or `String.to_existing_atom/1` on the input, so a crafted
  sort param can neither create atoms (atom-table exhaustion) nor crash on an
  unknown/non-column value; it just falls back to the default column.
  """
  @spec sort_field(String.t() | nil, [atom(), ...], atom()) :: atom()
  def sort_field(value, allowed, default) do
    Enum.find(allowed, default, &(Atom.to_string(&1) == value))
  end

  @doc """
  Resolves a client-supplied sort direction to `:asc` or `:desc`, defaulting to
  `:asc` for anything else.
  """
  @spec sort_direction(String.t() | nil) :: :asc | :desc
  def sort_direction("desc"), do: :desc
  def sort_direction(_value), do: :asc

  @doc """
  Toggles sort direction between "asc" and "desc".

  ## Examples

      iex> toggle_sort_direction("asc", "name", "name")
      {"name", "desc"}

      iex> toggle_sort_direction("desc", "name", "name")
      {"name", "asc"}

      iex> toggle_sort_direction("asc", "name", "email")
      {"email", "asc"}
  """
  def toggle_sort_direction(current_direction, current_key, new_key)
      when current_key == new_key do
    new_direction = if current_direction == "asc", do: "desc", else: "asc"
    {new_key, new_direction}
  end

  def toggle_sort_direction(_current_direction, _current_key, new_key) do
    {new_key, "asc"}
  end

  @doc """
  Filters a list of items based on searchable fields and a filter term.

  ## Examples

      users = [%{name: "Alice", email: "alice@example.com"}]
      search_fields = [:name, :email]
      filter_items(users, "alice", search_fields)
      # => [%{name: "Alice", email: "alice@example.com"}]
  """
  def filter_items(items, "", _search_fields), do: items

  def filter_items(items, filter, search_fields) when is_list(search_fields) do
    filter_lower = String.downcase(filter)

    Enum.filter(items, fn item ->
      Enum.any?(search_fields, fn field ->
        value = get_field_value(item, field) |> to_string() |> String.downcase()
        String.contains?(value, filter_lower)
      end)
    end)
  end

  @doc """
  Sorts items by a given field and direction.

  ## Examples

      users = [%{name: "Bob"}, %{name: "Alice"}]
      sort_items(users, "name", "asc", %{"name" => :name})
      # => [%{name: "Alice"}, %{name: "Bob"}]
  """
  def sort_items(items, sort_key, sort_direction, sort_map)
      when is_map(sort_map) do
    compare_fn = sort_compare_fn(sort_direction)
    sort_field = Map.get(sort_map, sort_key, sort_key)

    Enum.sort_by(
      items,
      fn item ->
        get_sort_value(item, sort_field)
      end,
      compare_fn
    )
  end

  @doc """
  Combines filtering and sorting in one operation.

  ## Examples

      users = [%{name: "Bob", email: "bob@test.com"}, %{name: "Alice", email: "alice@test.com"}]
      filter_and_sort(users, "test", [:email], "name", "asc", %{"name" => :name})
  """
  def filter_and_sort(
        items,
        filter,
        search_fields,
        sort_key,
        sort_direction,
        sort_map
      ) do
    items
    |> filter_items(filter, search_fields)
    |> sort_items(sort_key, sort_direction, sort_map)
  end

  # Private helpers

  defp get_field_value(item, field) when is_atom(field) do
    Map.get(item, field, "")
  end

  defp get_field_value(item, field) when is_function(field, 1) do
    field.(item)
  end

  defp get_field_value(_item, field) when is_binary(field) do
    field
  end

  defp get_sort_value(item, field) when is_atom(field) do
    item |> Map.get(field) |> normalize_sort_value()
  end

  defp get_sort_value(item, field) when is_function(field, 1) do
    item |> field.() |> normalize_sort_value()
  end

  defp get_sort_value(_item, field) do
    field
  end

  # `<=/>=` (used by sort_items's compare_fn) does Erlang structural term
  # comparison, which on `DateTime`/`NaiveDateTime`/`Date`/`Time` walks struct
  # keys alphabetically (day before month before year) and disagrees with
  # chronology at month boundaries. Convert to ISO 8601 strings, which sort
  # lexicographically the same as chronologically. The leading sentinel
  # (`0` for nil, `1` for present) keeps nil rows cleanly separate from any
  # real value, so the two can never tie at the comparator.
  defp normalize_sort_value(nil), do: {0, ""}
  defp normalize_sort_value(%DateTime{} = dt), do: {1, DateTime.to_iso8601(dt)}

  defp normalize_sort_value(%NaiveDateTime{} = dt),
    do: {1, NaiveDateTime.to_iso8601(dt)}

  defp normalize_sort_value(%Date{} = d), do: {1, Date.to_iso8601(d)}
  defp normalize_sort_value(%Time{} = t), do: {1, Time.to_iso8601(t)}
  defp normalize_sort_value(value), do: {1, value}
end
