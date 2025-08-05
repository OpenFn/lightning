defmodule Lightning.Credentials.SchemaDocument do
  @moduledoc """
  Provides facilities to dynamically create and validate a changeset for a given
  [Schema](`Lightning.Credentials.Schema`)
  """
  import Ecto.Changeset
  import Lightning.Helpers, only: [coerce_json_field: 2]

  alias Lightning.Credentials.Schema

  def changeset(document \\ %{}, attrs, schema: schema = %Schema{}) do
    processed_attrs = maybe_convert_to_map(schema, attrs)

    {document, schema.types}
    |> cast(processed_attrs, schema.fields)
    |> Schema.validate(schema)
  end

  defp maybe_convert_to_map(schema, attrs) do
    Enum.reduce(attrs, %{}, fn {key, value}, acc ->
      if Map.get(schema.types, String.to_atom(key)) == :map do
        coerce_json_field(%{key => value}, key)
        |> Map.get(key)
        |> then(&Map.put(acc, key, &1))
      else
        Map.put(acc, key, value)
      end
    end)
  end
end
