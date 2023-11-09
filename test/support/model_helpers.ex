defmodule Lightning.ModelHelpers do
  @doc """
  Replace an preloaded relation with an Ecto.Association.NotLoaded struct
  Our factories product models with loaded relations on them but our context
  functions don't preload credentials - this helps make make our factories
  uniform for these specific tests.

  > NOTE: It may be preferable to use `to_map/1` instead of this function.
  > as it is clearer about what the differences are between the two models.
  """
  def unload_relations(model, fields) when is_list(fields) do
    Enum.reduce(fields, model, fn field, acc_model ->
      unload_relation(acc_model, field)
    end)
  end

  def unload_relation(model, field) when is_atom(field) do
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

    Ecto.Changeset.change(struct, %{inserted_at: inserted_at})
    |> Lightning.Repo.update!()
  end

  @doc """
  Strips an Ecto model of its meta data and returns a map of its fields.

  Useful for comparing models in tests, where loaded relations (or preloads) may
  be different.
  """
  @spec to_map(Ecto.Schema.t()) :: map()
  def to_map(%{__meta__: _, __struct__: s} = model) do
    s.__schema__(:fields)
    |> Enum.map(fn field -> {field, model |> Map.get(field)} end)
    |> Enum.into(%{})
  end
end
