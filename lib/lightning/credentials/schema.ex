defmodule Lightning.Credentials.Schema do
  @moduledoc """
  Dynamic changeset module which uses a JsonSchema (parsed with `ExJsonSchema`)
  to validate credentials based on the schema provided.
  """
  alias ExJsonSchema.Validator
  import Ecto.Changeset

  @type t :: %__MODULE__{
          schema_root: ExJsonSchema.Schema.Root.t(),
          types: Ecto.Changeset.types(),
          data: Ecto.Changeset.data()
        }

  defstruct [:schema_root, :types, :data]

  @spec new(schema :: %{String.t() => any()}, data :: %{String.t() => any()}) ::
          __MODULE__.t()
  def new(schema, data \\ %{}) when is_map(schema) do
    if is_nil(data) do
      raise "#{__MODULE__}.new/2 got nil for data, expects a map."
    end

    schema_root = ExJsonSchema.Schema.resolve(schema)
    types = get_types(schema_root)
    data = build_body(types, data)

    struct!(__MODULE__, schema_root: schema_root, types: types, data: data)
  end

  def changeset(%__MODULE__{} = schema, attrs) do
    changeset =
      {schema.data, schema.types}
      |> cast(attrs, Map.keys(schema.types))

    validation =
      Validator.validate(
        schema.schema_root,
        apply_changes(changeset) |> stringify_keys(),
        error_formatter: false
      )

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
        add_error(changeset, field, "expected to be a URI")

      %{missing: fields} ->
        Enum.reduce(fields, changeset, fn field, changeset ->
          add_error(changeset, field, "can't be blank")
        end)

      %{actual: 0, expected: _} ->
        add_error(changeset, field, "can't be blank")

      %{actual: "null", expected: ["string"]} ->
        add_error(changeset, field, "can't be blank")
    end
  end

  defp get_types(schema_root) do
    schema_root.schema
    |> Map.get("properties", [])
    |> Enum.map(fn {k, properties} ->
      {k |> String.to_atom(),
       Map.get(properties, "type", "string") |> String.to_atom()}
    end)
    |> Enum.reverse()
    |> Map.new()
  end

  @spec build_body(types :: Ecto.Changeset.types(), initial :: map()) ::
          Ecto.Changeset.data()
  def build_body(types, initial) do
    Map.new(types, fn {k, _type} ->
      {k, Map.get(initial, k |> to_string(), nil)}
    end)
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
