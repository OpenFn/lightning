defmodule Lightning.Credentials.Schema do
  alias ExJsonSchema.Validator
  alias Ecto.Changeset

  @spec validate(
          schema :: ExJsonSchema.Schema.Root.t(),
          attrs :: %{required(binary) => term} | %{required(atom) => term}
        ) :: Ecto.Changeset.t()
  def validate(schema, attrs) do
    changeset(schema, attrs)
  end

  def changeset(schema, attrs) do
    validation = Validator.validate(schema, attrs, error_formatter: false)

    types = get_types(schema)

    changeset =
      {types |> Map.keys() |> Enum.map(&{&1, nil}) |> Map.new(), types}
      |> Changeset.cast(attrs, Map.keys(types))

    case validation do
      :ok ->
        changeset

      {:error, errors} when is_list(errors) ->
        Enum.reduce(errors, changeset, &error_to_changeset/2)
    end
  end

  defp error_to_changeset(%{path: path, error: error}, changeset) do
    field = String.slice(path, 2..-1) |> String.to_existing_atom()

    case error do
      %{expected: "uri"} ->
        Changeset.add_error(changeset, field, "Expected to be a URI")

      %{missing: fields} ->
        Enum.reduce(fields, changeset, fn field, changeset ->
          Changeset.add_error(changeset, field, "Can't be blank")
        end)

      %{actual: 0, expected: _} ->
        Changeset.add_error(changeset, field, "Can't be blank")
    end
  end

  defp get_types(schema_root) do
    schema_root.schema
    |> Map.get("properties")
    |> Enum.map(fn {k, properties} ->
      {k |> String.to_atom(), Map.get(properties, "type") |> String.to_atom()}
    end)
    |> Enum.reverse()
    |> Map.new()
  end
end
