defmodule Lightning.HelpersTest do
  use ExUnit.Case, async: true

  import Lightning.Helpers, only: [coerce_json_field: 2]

  alias Ecto.Changeset
  alias Lightning.Helpers

  test "coerce_json_field/2 will transform a json string inside a map by it's key" do
    input = %{
      "body" =>
        "{\n  \"a\": 1,\n  \"b\": {\n    \"sadio\": true, \"other\": [1,2,\"bah\"]\n  }\n}",
      "name" => "My Credential"
    }

    assert coerce_json_field(input, "body") == %{
             "body" => %{
               "a" => 1,
               "b" => %{"other" => [1, 2, "bah"], "sadio" => true}
             },
             "name" => "My Credential"
           }
  end

  test "coerce_json_field/2 will not do anything if the json string inside a map is invalid" do
    input = %{name: "Sadio Mane", stats: "goals:126, teams: Metz, Liverpool"}

    assert coerce_json_field(input, "stats") == %{
             name: "Sadio Mane",
             stats: "goals:126, teams: Metz, Liverpool"
           }
  end

  test "coerce_json_field/2 will not do anything if the given key doesn't exist" do
    input = %{name: "Sadio Mane", stats: "goals:126, teams: Metz, Liverpool"}

    assert coerce_json_field(input, "somekey") == %{
             name: "Sadio Mane",
             stats: "goals:126, teams: Metz, Liverpool"
           }
  end

  test "coerce_json_field/2 will not do anything if the value of the given key is nil" do
    input = %{name: "Sadio Mane", stats: nil}

    assert coerce_json_field(input, "stats") == %{
             name: "Sadio Mane",
             stats: nil
           }
  end

  test "coerce_json_field/2 will not do anything if the value of the given key is not a string" do
    input = %{name: "Sadio Mane", goals: 123}

    assert coerce_json_field(input, "goals") == %{
             name: "Sadio Mane",
             goals: 123
           }
  end

  describe "copy_error/4" do
    test "copies an error from one key to another" do
      changeset = %Changeset{errors: [name: {"has already been taken", []}]}
      updated_changeset = Helpers.copy_error(changeset, :name, :raw_name)

      assert updated_changeset.errors[:name] == {"has already been taken", []}

      assert updated_changeset.errors[:raw_name] ==
               {"has already been taken", []}
    end

    test "returns the changeset unchanged if original_key does not exist" do
      changeset = %Changeset{errors: [email: {"is invalid", []}]}
      updated_changeset = Helpers.copy_error(changeset, :name, :raw_name)

      assert updated_changeset == changeset
      refute Keyword.has_key?(updated_changeset.errors, :raw_name)
    end

    test "overwrites the new_key error if it exists and overwrite is true" do
      changeset = %Changeset{
        errors: [
          name: {"has already been taken", []},
          raw_name: {"is invalid", []}
        ]
      }

      updated_changeset = Helpers.copy_error(changeset, :name, :raw_name)

      assert updated_changeset.errors[:raw_name] ==
               {"has already been taken", []}
    end

    test "does not overwrite the new_key error if overwrite is false" do
      changeset = %Changeset{
        errors: [
          name: {"has already been taken", []},
          raw_name: {"is invalid", []}
        ]
      }

      updated_changeset =
        Helpers.copy_error(changeset, :name, :raw_name, overwrite: false)

      assert updated_changeset.errors[:raw_name] == {"is invalid", []}
    end

    test "returns the changeset unchanged if new_key already exists and overwrite is false" do
      changeset = %Changeset{
        errors: [
          name: {"has already been taken", []},
          raw_name: {"is invalid", []}
        ]
      }

      updated_changeset =
        Helpers.copy_error(changeset, :name, :raw_name, overwrite: false)

      assert updated_changeset.errors[:raw_name] == {"is invalid", []}
    end
  end

  describe "url_safe_name/1" do
    test "returns an empty string when given nil" do
      assert Helpers.url_safe_name(nil) == ""
    end

    test "converts a simple string to lowercase and replaces spaces" do
      assert Helpers.url_safe_name("My Project") == "my-project"
    end

    test "removes special characters and replaces them with hyphens" do
      assert Helpers.url_safe_name("My@#Project!!") == "my-project"
    end

    test "trims leading and trailing hyphens" do
      assert Helpers.url_safe_name("--My Project--") == "my-project"
    end

    test "preserves international characters" do
      assert Helpers.url_safe_name("Éléphant") == "éléphant"
    end

    test "handles a string with multiple special characters" do
      assert Helpers.url_safe_name("Hello, World! 123") == "hello-world-123"
    end

    test "handles a string with underscores and periods" do
      assert Helpers.url_safe_name("file_name.version_1.0") ==
               "file_name.version_1.0"
    end

    test "replaces multiple spaces or special characters with a single hyphen" do
      assert Helpers.url_safe_name("My   Project") == "my-project"
      assert Helpers.url_safe_name("My--Project!!") == "my--project"
    end

    test "handles a string with only special characters and removes them" do
      assert Helpers.url_safe_name("###!!!") == ""
    end

    test "keeps numbers intact in the string" do
      assert Helpers.url_safe_name("Project 2023") == "project-2023"
    end
  end
end
