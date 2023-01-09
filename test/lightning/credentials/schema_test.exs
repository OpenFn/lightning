defmodule Lightning.Credentials.SchemaTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials.Schema

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

      assert schema.data == %{
               hostUrl: nil,
               password: nil,
               username: nil,
               number: nil
             }

      schema = Schema.new(schema_map, %{"username" => "initial_user"})

      assert schema.types == %{
               hostUrl: :string,
               password: :string,
               username: :string,
               number: :integer
             }

      assert schema.data == %{
               hostUrl: nil,
               password: nil,
               username: "initial_user",
               number: nil
             }
    end
  end

  describe "changeset/2" do
    test "can ", %{schema_map: schema_map} do
      schema = Schema.new(schema_map)

      changeset =
        Schema.changeset(schema, %{"foo" => "bar", "password" => "pass"})

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
      assert {:username, ["can't be blank"]} in errors
      assert {:hostUrl, ["can't be blank"]} in errors
      assert {:number, ["can't be blank"]} in errors

      schema = Schema.new(schema_map, %{"username" => "initial_username"})

      changeset =
        Schema.changeset(schema, %{
          "password" => "pass",
          "hostUrl" => "http://localhost",
          "number" => 100
        })

      assert changeset.valid?
    end
  end
end
