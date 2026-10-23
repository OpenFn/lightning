defmodule LightningWeb.Live.Helpers.TableHelpers do
  @moduledoc """
  Helpers for resolving a table's sort column and direction from the URL.
  """

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
end
