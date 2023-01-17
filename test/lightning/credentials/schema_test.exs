defmodule Lightning.Credentials.SchemaTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials.Schema
  alias Lightning.Credentials.SchemaDocument

  setup do
    schema_map =
      """
      {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "properties": {
          "username": {
            "type": "string",
            "description": "The username used to log in"
          },
          "password": {
            "type": "string",
            "description": "The password used to log in",
            "writeOnly": true
          },
          "hostUrl": {
            "type": "string",
            "description": "The password used to log in",
            "format": "uri"
          },
          "number": {
            "type": "integer",
            "description": "A number to log in"
          }
        },
        "type": "object",
        "additionalProperties": true,
        "required": ["hostUrl", "password", "username", "number"]
      }
      """
      |> Jason.decode!()

    %{schema_map: schema_map}
  end

  describe "new/1" do
    test "creates a struct containing the schema, types and data", %{
      schema_map: schema_map
    } do
      schema = Schema.new(schema_map)

      assert schema.types == %{
               hostUrl: :string,
               password: :string,
               username: :string,
               number: :integer
             }

      schema = Schema.new(schema_map, "foo")

      assert schema.name == "foo"

      assert schema.types == %{
               hostUrl: :string,
               password: :string,
               username: :string,
               number: :integer
             }
    end
  end

  describe "SchemaDocument.changeset/3" do
    setup %{schema_map: schema_map} do
      %{schema: Schema.new(schema_map, "test")}
    end

    test "can ", %{schema: schema} do
      changeset =
        SchemaDocument.changeset(%{}, %{"foo" => "bar", "password" => "pass"},
          schema: schema
        )

      refute changeset.valid?

      refute Ecto.Changeset.get_field(changeset, "foo"),
             "Shouldn't find undeclared fields in changeset"

      refute Ecto.Changeset.get_field(changeset, :foo),
             "Shouldn't find undeclared fields in changeset"

      refute Ecto.Changeset.get_field(changeset, "password"),
             "Shouldn't be able to access fields via string keys"

      assert Ecto.Changeset.get_field(changeset, :password),
             "Should be able to find existing keys via atoms"

      errors = errors_on(changeset)
      assert {"username", ["can't be blank"]} in errors
      assert {"hostUrl", ["can't be blank"]} in errors
      assert {"number", ["can't be blank"]} in errors

      changeset =
        SchemaDocument.changeset(
          %{},
          %{
            "username" => "initial",
            "password" => "pass",
            "hostUrl" => "http://localhost",
            "number" => 100
          },
          schema: schema
        )

      assert changeset.valid?
    end
  end
end
