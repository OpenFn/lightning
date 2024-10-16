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
end
