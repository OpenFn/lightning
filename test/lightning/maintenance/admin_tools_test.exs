defmodule Lightning.AdminToolstest do
  use ExUnit.Case, async: true

  alias Lightning.AdminTools

  describe "generate_iso_weeks" do
    test "returns list of weeks when both dates are Mondays" do
      expected_weeks = [
        {"2023", "08", "2023-02-20", "2023-02-27"},
        {"2023", "09", "2023-02-27", "2023-03-06"},
        {"2023", "10", "2023-03-06", "2023-03-13"},
        {"2023", "11", "2023-03-13", "2023-03-20"},
        {"2023", "12", "2023-03-20", "2023-03-27"}
      ]

      weeks = AdminTools.generate_iso_weeks(~D[2023-02-20], ~D[2023-03-20])

      assert weeks == expected_weeks
    end

    test "returns list of weeks when start date is a Monday" do
      expected_weeks = [
        {"2023", "08", "2023-02-20", "2023-02-27"},
        {"2023", "09", "2023-02-27", "2023-03-06"},
        {"2023", "10", "2023-03-06", "2023-03-13"},
        {"2023", "11", "2023-03-13", "2023-03-20"},
        {"2023", "12", "2023-03-20", "2023-03-27"}
      ]

      weeks = AdminTools.generate_iso_weeks(~D[2023-02-20], ~D[2023-03-23])

      assert weeks == expected_weeks
    end

    test "returns list of weeks when end date is a Monday" do
      expected_weeks = [
        {"2023", "08", "2023-02-20", "2023-02-27"},
        {"2023", "09", "2023-02-27", "2023-03-06"},
        {"2023", "10", "2023-03-06", "2023-03-13"},
        {"2023", "11", "2023-03-13", "2023-03-20"},
        {"2023", "12", "2023-03-20", "2023-03-27"}
      ]

      weeks = AdminTools.generate_iso_weeks(~D[2023-02-22], ~D[2023-03-20])

      assert weeks == expected_weeks
    end

    test "returns list of weeks when neither day is a Monday" do
      expected_weeks = [
        {"2023", "08", "2023-02-20", "2023-02-27"},
        {"2023", "09", "2023-02-27", "2023-03-06"},
        {"2023", "10", "2023-03-06", "2023-03-13"},
        {"2023", "11", "2023-03-13", "2023-03-20"},
        {"2023", "12", "2023-03-20", "2023-03-27"}
      ]

      weeks = AdminTools.generate_iso_weeks(~D[2023-02-22], ~D[2023-03-23])

      assert weeks == expected_weeks
    end
  end
end
