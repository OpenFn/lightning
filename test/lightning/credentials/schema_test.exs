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
      |> Jason.decode!(objects: :ordered_objects)

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

      assert schema.fields == [:username, :password, :hostUrl, :number]
    end
  end

  describe "validate/2" do
    test "returns a changeset with 2 expected formats" do
      schema = Schema.new(postgres_schema_json(), "postgres")

      changeset =
        Ecto.Changeset.put_change(
          %Ecto.Changeset{data: %{}, types: schema.types},
          :host,
          "l"
        )

      assert %Ecto.Changeset{errors: errors} = Schema.validate(changeset, schema)

      assert Enum.any?(
               errors,
               &(&1 == {:host, {"expected to be a URI or an IPv4 address", []}})
             )
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

  defp postgres_schema_json do
    """
    {
      "$schema": "http://json-schema.org/draft-07/schema#",
      "properties": {
        "host": {
          "title": "Host",
          "type": "string",
          "description": "Postgres instance host URL or IP address",
          "minLength": 1,
          "anyOf": [
            {
              "format": "uri"
            },
            {
              "format": "ipv4"
            }
          ],
          "examples": [
            "https://some-host.compute-1.amazonaws.com",
            "201.220.61.246"
          ]
        },
        "port": {
          "title": "Port",
          "type": "integer",
          "default": 5432,
          "description": "Database instance port",
          "minLength": 1,
          "examples": [
            5432
          ]
        },
        "database": {
          "title": "Database",
          "type": "string",
          "description": "The database name",
          "minLength": 1,
          "examples": [
            "demo-db"
          ]
        },
        "user": {
          "title": "User",
          "type": "string",
          "description": "User name",
          "minLength": 1,
          "examples": [
            "admin"
          ]
        },
        "password": {
          "title": "Password",
          "type": "string",
          "description": "Password",
          "writeOnly": true,
          "minLength": 1,
          "examples": [
            "@super(!)Secretpass"
          ]
        },
        "ssl": {
          "title": "Use SSL",
          "type": "boolean",
          "examples": [
            true
          ]
        },
        "allowSelfSignedCert": {
          "title": "Allow self-signed certificate",
          "type": "boolean",
          "examples": [
            true
          ]
        }
      },
      "type": "object",
      "additionalProperties": true,
      "required": [
        "host",
        "port",
        "database"
      ]
    }
    """
  end
end
