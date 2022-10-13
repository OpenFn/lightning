defmodule Lightning.HelpersTest do
  use ExUnit.Case, async: true
  use Lightning.DataCase, async: true

  import Lightning.Helpers,
    only: [
      coerce_json_field: 2,
      cron_values_to_expression: 1,
      cron_expression_to_values: 1
    ]

  import Lightning.JobsFixtures

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

  test "cron_expression_to_values/1" do
    assert job_fixture(trigger: %{type: :cron, cron_expression: "5 0 * 8 *"})
           |> Map.get(:trigger)
           |> cron_expression_to_values()
           |> Map.get("periodicity") == "custom"

    assert job_fixture(trigger: %{type: :cron, cron_expression: "5 0 8 * *"})
           |> Map.get(:trigger)
           |> cron_expression_to_values() == %{
             "periodicity" => "monthly",
             "minutes" => "5",
             "hours" => "0",
             "monthday" => "8",
             "type" => "cron"
           }

    assert job_fixture(trigger: %{type: :cron, cron_expression: "34 * * * *"})
           |> Map.get(:trigger)
           |> cron_expression_to_values() == %{
             "periodicity" => "hourly",
             "minutes" => "34",
             "type" => "cron"
           }

    assert job_fixture(trigger: %{type: :cron, cron_expression: "5 0 * * 6"})
           |> Map.get(:trigger)
           |> cron_expression_to_values() == %{
             "periodicity" => "weekly",
             "minutes" => "5",
             "hours" => "0",
             "weekday" => "6",
             "type" => "cron"
           }

    assert job_fixture(trigger: %{type: :cron, cron_expression: "50 0 * * *"})
           |> Map.get(:trigger)
           |> cron_expression_to_values() == %{
             "periodicity" => "daily",
             "minutes" => "50",
             "hours" => "0",
             "type" => "cron"
           }

    assert job_fixture(trigger: %{type: :webhook})
           |> Map.get(:trigger)
           |> cron_expression_to_values()
           |> Map.get(:type) == :webhook

    assert cron_expression_to_values(nil) == %{}
  end

  test "cron_values_to_expression/1" do
    assert cron_values_to_expression(%{
             "weekday" => 3,
             "hours" => 12,
             "minutes" => 45
           }) == %{
             "cron_expression" => "45 12 * * 3",
             "hours" => 12,
             "minutes" => 45,
             "weekday" => 3
           }

    assert cron_values_to_expression(%{"minutes" => 45}) == %{
             "cron_expression" => "45 * * * *",
             "minutes" => 45
           }

    assert cron_values_to_expression(%{
             "hours" => 12,
             "minutes" => 45
           }) == %{
             "cron_expression" => "45 12 * * *",
             "hours" => 12,
             "minutes" => 45
           }

    assert cron_values_to_expression(%{
             "monthday" => 3,
             "hours" => 12,
             "minutes" => 45
           }) == %{
             "cron_expression" => "45 12 3 * *",
             "hours" => 12,
             "minutes" => 45,
             "monthday" => 3
           }

    assert cron_values_to_expression(%{
             "type" => "cron",
             "cron_expression" => "* * * * *"
           }) == %{
             "cron_expression" => "* * * * *",
             "type" => "cron"
           }
  end
end
