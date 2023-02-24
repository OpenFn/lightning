defmodule Lightning.Credentials.Schema do
  @moduledoc """
  Structure that can parse JsonSchemas (using `ExJsonSchema`) and validate
  changesets for a given schema.
  """

  alias ExJsonSchema.Validator
  alias Ecto.Changeset

  @type t :: %__MODULE__{
          name: String.t() | nil,
          root: ExJsonSchema.Schema.Root.t(),
          types: Ecto.Changeset.types(),
          fields: [String.t()]
        }

  defstruct [:name, :root, :types, :fields]

  @spec new(json_schema :: %{String.t() => any()}, name :: String.t() | nil) ::
          __MODULE__.t()
  def new(json_schema, name \\ nil) when is_map(json_schema) do
    root = ExJsonSchema.Schema.resolve(json_schema)
    types = get_types(root)
    fields = Map.keys(types)

    struct!(__MODULE__, name: name, root: root, types: types, fields: fields)
  end

  @spec validate(changeset :: Ecto.Changeset.t(), schema :: __MODULE__.t()) ::
          Ecto.Changeset.t()
  def validate(changeset, %__MODULE__{} = schema) do
    validation =
      Validator.validate(
        schema.root,
        Changeset.apply_changes(changeset) |> stringify_keys(),
        error_formatter: false
      )

    case validation do
      :ok ->
        changeset

      {:error, errors} when is_list(errors) ->
        Enum.reduce(errors, changeset, &error_to_changeset/2)
    end
  end

  def properties(schema, field) do
    schema.root.schema
    |> Map.get("properties")
    |> Map.get(field |> to_string())
  end

  def required?(schema, field) do
    field = to_string(field)

    schema.root.schema
    |> Map.get("required", [])
    |> Enum.any?(fn required_field -> field == required_field end)
  end

  defp error_to_changeset(%{path: path, error: error}, changeset) do
    field = String.slice(path, 2..-1) |> String.to_existing_atom()

    case error do
      %{expected: "uri"} ->
        Changeset.add_error(changeset, field, "expected to be a URI")

      %{missing: fields} ->
        Enum.reduce(fields, changeset, fn field, changeset ->
          Changeset.add_error(changeset, field, "can't be blank")
        end)

      %{actual: 0, expected: _} ->
        Changeset.add_error(changeset, field, "can't be blank")

      %{actual: "null", expected: expected} when is_list(expected) ->
        Changeset.add_error(changeset, field, "can't be blank")
    end
  end

  defp get_types(root) do
    root.schema
    |> Map.get("properties", [])
    |> Enum.map(fn {k, properties} ->
      {k |> String.to_atom(),
       Map.get(properties, "type", "string") |> String.to_atom()}
    end)
    |> Enum.reverse()
    |> Map.new()
  end

  defp stringify_keys(data) when is_map(data) do
    Enum.reduce(data, %{}, fn
      {key, value}, acc when is_atom(key) ->
        Map.put(acc, key |> to_string(), value)

      {key, value}, acc when is_binary(key) ->
        Map.put(acc, key, value)
    end)
  end
end
