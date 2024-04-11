defmodule Lightning.HelpersTest do
  use ExUnit.Case, async: false

  import Lightning.ApplicationHelpers, only: [put_temporary_env: 3]
  import Lightning.Helpers, only: [coerce_json_field: 2, version_data: 0]

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

  describe "version_data" do
    test "returns data that can be used to represent the instance version" do
      put_temporary_env(:lightning, :image_info,
        branch: "foo-bar",
        commit: "abc123",
        image_tag: "vx.y.z"
      )

      expected = %{
        branch: "foo-bar",
        commit: "abc123",
        image: "vx.y.z",
        spec_version: "v#{Application.spec(:lightning, :vsn)}"
      }

      assert version_data() == expected
    end

    test "correctly deals with nil values" do
      put_temporary_env(:lightning, :image_info,
        branch: nil,
        commit: nil,
        image_tag: nil
      )

      expected = %{
        branch: nil,
        commit: nil,
        image: nil,
        spec_version: "v#{Application.spec(:lightning, :vsn)}"
      }

      assert version_data() == expected
    end
  end
end
