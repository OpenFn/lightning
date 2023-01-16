defmodule Lightning.Credentials.SchemaDocument do
  alias Lightning.Credentials.Schema
  import Ecto.Changeset

  def changeset(document, attrs, schema: schema = %Schema{}) do
    {document, schema.types}
    |> cast(attrs, schema.fields)
    |> Schema.validate(schema)
  end
end
