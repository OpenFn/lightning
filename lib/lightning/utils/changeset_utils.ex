defmodule Lightning.ChangesetUtils do
  @moduledoc """
  Extra functions for Ecto.Changeset.
  """

  import Ecto.Changeset

  @doc """
  Puts a new change in the changeset if the field is not already set.

  NOTE: This function considers a field with a `nil` value as not set.
  """
  @spec put_new_change(Ecto.Changeset.t(), atom(), any()) :: Ecto.Changeset.t()
  def put_new_change(changeset, field, value) do
    if get_change(changeset, field) do
      changeset
    else
      put_change(changeset, field, value)
    end
  end

  @doc """
  Puts a new change in the changeset if the params have the field.

  Useful when params don't have a given key and you don't want to set the
  field to `nil`.
  """
  @spec put_if_provided(Ecto.Changeset.t(), atom(), map()) :: Ecto.Changeset.t()
  def put_if_provided(changeset, field, params) do
    if Map.has_key?(params, field) do
      put_change(changeset, field, Map.get(params, field))
    else
      changeset
    end
  end
end
