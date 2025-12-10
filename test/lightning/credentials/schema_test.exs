defmodule Lightning.Credentials.SchemaTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials
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
            "description": "The host URL",
            "format": "uri"
          },
          "number": {
            "type": "integer",
            "description": "Any other number field"
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
    test "successfully validates field with json schema email format" do
      schema = Credentials.get_schema("godata")

      changeset =
        Ecto.Changeset.put_change(
          %Ecto.Changeset{
            data: %{password: "1234", apiUrl: "http://addr"},
            types: schema.types
          },
          :email,
          "some@email.com"
        )

      assert %Ecto.Changeset{errors: [], changes: %{email: "some@email.com"}} =
               Schema.validate(changeset, schema)
    end

    test "returns a changeset with 2 expected formats" do
      schema = Credentials.get_schema("postgresql")

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

    test "returns a changeset with 1 expected format and 2 allowed types" do
      schema = Credentials.get_schema("http")

      changeset =
        Ecto.Changeset.put_change(
          %Ecto.Changeset{data: %{}, types: schema.types},
          :baseUrl,
          "not a uri"
        )

      assert %Ecto.Changeset{errors: errors} = Schema.validate(changeset, schema)

      assert Enum.any?(
               errors,
               &(&1 == {:baseUrl, {"expected to be a URI", []}})
             )
    end

    test "treats object types as text (TEMP FIX)" do
      schema = Credentials.get_schema("http")

      assert schema.types == %{
               username: :string,
               password: :string,
               tls: :map,
               baseUrl: :string,
               access_token: :string
             }
    end

    test "returns a changeset with expected email format" do
      schema = Credentials.get_schema("godata")

      changeset =
        Ecto.Changeset.put_change(
          %Ecto.Changeset{data: %{}, types: schema.types},
          :email,
          "not-an-email@"
        )

      assert %Ecto.Changeset{errors: errors} = Schema.validate(changeset, schema)

      assert Enum.any?(
               errors,
               &(&1 == {:email, {"expected to be an email", []}})
             )
    end

    test "returns a changeset with no expected format and 2 allowed types" do
      schema = Credentials.get_schema("dhis2")

      changeset =
        Ecto.Changeset.put_change(
          %Ecto.Changeset{data: %{}, types: schema.types},
          :apiVersion,
          "v2"
        )

      assert %Ecto.Changeset{errors: errors} = Schema.validate(changeset, schema)

      refute Enum.find(errors, fn {field, {_message, _list}} ->
               field == "apiVersion"
             end)
    end

    test "accepts valid JSON object string for object type fields" do
      schema =
        Schema.new(%{
          "properties" => %{
            "config" => %{"type" => "object"}
          }
        })

      changeset =
        %Ecto.Changeset{
          data: %{},
          types: %{config: :map},
          valid?: true
        }
        |> Ecto.Changeset.put_change(
          :config,
          ~s({"key": "value", "nested": {"foo": "bar"}})
        )

      validated = Schema.validate(changeset, schema)

      assert validated.valid?
      assert validated.errors == []
    end

    test "adds error for malformed JSON when object type expected" do
      schema =
        Schema.new(%{
          "properties" => %{
            "settings" => %{"type" => "object"}
          }
        })

      changeset =
        %Ecto.Changeset{
          data: %{},
          types: %{settings: :map}
        }
        |> Ecto.Changeset.put_change(:settings, "not valid json{")

      validated = Schema.validate(changeset, schema)

      refute validated.valid?
      assert {:settings, {"invalid JSON", []}} in validated.errors
    end

    test "adds error when JSON array provided for object type field" do
      schema =
        Schema.new(%{
          "properties" => %{
            "data" => %{"type" => "object"}
          }
        })

      changeset =
        %Ecto.Changeset{
          data: %{},
          types: %{data: :map}
        }
        |> Ecto.Changeset.put_change(:data, ~s([1, 2, 3]))

      validated = Schema.validate(changeset, schema)

      refute validated.valid?
      assert {:data, {"invalid JSON", []}} in validated.errors
    end

    test "handles various JSON edge cases for object type validation" do
      schema =
        Schema.new(%{
          "properties" => %{
            "config" => %{"type" => "object"}
          }
        })

      changeset_null =
        %Ecto.Changeset{data: %{}, types: %{config: :map}, valid?: true}
        |> Ecto.Changeset.put_change(:config, "null")

      validated_null = Schema.validate(changeset_null, schema)
      assert {:config, {"invalid JSON", []}} in validated_null.errors

      changeset_string =
        %Ecto.Changeset{data: %{}, types: %{config: :map}, valid?: true}
        |> Ecto.Changeset.put_change(:config, ~s("just a string"))

      validated_string = Schema.validate(changeset_string, schema)
      assert {:config, {"invalid JSON", []}} in validated_string.errors

      changeset_number =
        %Ecto.Changeset{data: %{}, types: %{config: :map}, valid?: true}
        |> Ecto.Changeset.put_change(:config, "123")

      validated_number = Schema.validate(changeset_number, schema)
      assert {:config, {"invalid JSON", []}} in validated_number.errors

      changeset_bool =
        %Ecto.Changeset{data: %{}, types: %{config: :map}, valid?: true}
        |> Ecto.Changeset.put_change(:config, "true")

      validated_bool = Schema.validate(changeset_bool, schema)
      assert {:config, {"invalid JSON", []}} in validated_bool.errors

      changeset_empty =
        %Ecto.Changeset{data: %{}, types: %{config: :map}, valid?: true}
        |> Ecto.Changeset.put_change(:config, "{}")

      validated_empty = Schema.validate(changeset_empty, schema)
      assert validated_empty.valid?
      assert validated_empty.errors == []
    end

    test "handles non-string values for object type fields" do
      schema =
        Schema.new(%{
          "properties" => %{
            "config" => %{"type" => "object"}
          }
        })

      changeset =
        %Ecto.Changeset{
          data: %{},
          types: %{config: :map}
        }
        |> Ecto.Changeset.put_change(:config, 123)

      validated = Schema.validate(changeset, schema)

      refute validated.valid?
      assert {:config, {"must be an object", []}} in validated.errors
    end

    test "accepts valid JSON object string and continues without error" do
      schema =
        Schema.new(%{
          "properties" => %{
            "metadata" => %{"type" => "object"}
          }
        })

      changeset =
        %Ecto.Changeset{
          data: %{},
          types: %{metadata: :map},
          valid?: true
        }
        |> Ecto.Changeset.put_change(
          :metadata,
          ~s({"valid": "json", "with": {"nested": "object"}})
        )

      validated = Schema.validate(changeset, schema)

      assert validated.valid?
      assert validated.errors == []
    end

    test "handles non-binary input to validate_json_object" do
      schema =
        Schema.new(%{
          "properties" => %{
            "settings" => %{"type" => "object"}
          }
        })

      changeset_atom =
        %Ecto.Changeset{
          data: %{},
          types: %{settings: :map},
          valid?: true
        }
        |> Ecto.Changeset.put_change(:settings, :not_a_string)

      validated = Schema.validate(changeset_atom, schema)
      refute validated.valid?
      assert {:settings, {"must be an object", []}} in validated.errors

      changeset_nil = %Ecto.Changeset{
        data: %{settings: nil},
        changes: %{},
        types: %{settings: :map},
        valid?: true
      }

      validated_nil = Schema.validate(changeset_nil, schema)
      refute validated_nil.valid?
      assert {:settings, {"can't be blank", []}} in validated_nil.errors

      changeset_map =
        %Ecto.Changeset{
          data: %{},
          types: %{settings: :map},
          valid?: true
        }
        |> Ecto.Changeset.put_change(:settings, %{already: "decoded"})

      validated_map = Schema.validate(changeset_map, schema)

      assert validated_map.valid?
      assert validated_map.errors == []
    end
  end

  describe "SchemaDocument.changeset/3" do
    setup %{schema_map: schema_map} do
      %{schema: Schema.new(schema_map, "test")}
    end

    test "can ", %{schema: schema} do
      changeset =
        SchemaDocument.changeset(%{"foo" => "bar", "password" => "pass"},
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
      assert %{username: ["can't be blank"]} = errors
      assert %{hostUrl: ["can't be blank"]} = errors
      assert %{number: ["can't be blank"]} = errors

      changeset =
        SchemaDocument.changeset(
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
