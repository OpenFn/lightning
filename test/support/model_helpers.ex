defmodule Lightning.ModelHelpers do
  @doc """
  Replace an preloaded relation with an Ecto.Association.NotLoaded struct
  Our factories product models with loaded relations on them but our context
  functions don't preload credentials - this helps make make our factories
  uniform for these specific tests.
  """
  def unload_relation(model, field) do
    model
    |> Map.replace(field, model.__struct__.__struct__ |> Map.get(field))
  end

  @doc """
  Shift the inserted_at of a given model.
  """
  @spec shift_inserted_at!(map(), list()) :: map()
  def shift_inserted_at!(struct, shift_attrs) do
    inserted_at =
      Map.get(struct, :inserted_at)
      |> Timex.shift(shift_attrs)
      |> Timex.to_naive_datetime()
      |> NaiveDateTime.truncate(:second)

    Ecto.Changeset.change(struct, %{inserted_at: inserted_at})
    |> Lightning.Repo.update!()
  end
end
