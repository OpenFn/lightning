defmodule Lightning.Credentials.SchemaDocument do
  @moduledoc """
  Provides facilities to dynamically create and validate a changeset for a given
  [Schema](`Lightning.Credentials.Schema`)
  """

  alias Lightning.Credentials.Schema
  import Ecto.Changeset

  def changeset(document \\ %{}, attrs, schema: schema = %Schema{}) do
    {document, schema.types}
    |> cast(attrs, schema.fields)
    |> Schema.validate(schema)
  end
end
