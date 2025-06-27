defmodule LightningWeb.Live.Helpers.TableHelpers do
  @moduledoc """
  Utilities for simplifying common table operations like sorting and filtering.

  This module provides reusable functions to reduce complexity in LiveView components
  that handle sortable, filterable tables.
  """

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
  Toggles sort direction between "asc" and "desc".

  ## Examples

      iex> toggle_sort_direction("asc", "name", "name")
      {"name", "desc"}

      iex> toggle_sort_direction("desc", "name", "name")
      {"name", "asc"}

      iex> toggle_sort_direction("asc", "name", "email")
      {"email", "asc"}
  """
  def toggle_sort_direction(current_direction, current_key, new_key) when current_key == new_key do
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
  def sort_items(items, sort_key, sort_direction, sort_map) when is_map(sort_map) do
    compare_fn = sort_compare_fn(sort_direction)
    sort_field = Map.get(sort_map, sort_key, sort_key)

    Enum.sort_by(items, fn item ->
      get_sort_value(item, sort_field)
    end, compare_fn)
  end

  @doc """
  Combines filtering and sorting in one operation.

  ## Examples

      users = [%{name: "Bob", email: "bob@test.com"}, %{name: "Alice", email: "alice@test.com"}]
      filter_and_sort(users, "test", [:email], "name", "asc", %{"name" => :name})
  """
  def filter_and_sort(items, filter, search_fields, sort_key, sort_direction, sort_map) do
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
    case Map.get(item, field) do
      nil -> ""
      value when is_binary(value) -> value
      value -> value
    end
  end

  defp get_sort_value(item, field) when is_function(field, 1) do
    field.(item)
  end

  defp get_sort_value(_item, field) do
    field
  end
end
