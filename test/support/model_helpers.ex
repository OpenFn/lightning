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
end
