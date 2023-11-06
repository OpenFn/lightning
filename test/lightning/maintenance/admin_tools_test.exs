defmodule Lightning.AdminToolstest do
  use ExUnit.Case, async: true

  alias Lightning.AdminTools

  describe "generate_iso_weeks" do
    test "returns a list of weeks between two given dates" do
      expected_weeks = [
        {"2023", "40", "2023-10-02", "2023-10-09"},
        {"2023", "41", "2023-10-09", "2023-10-16"},
        {"2023", "42", "2023-10-16", "2023-10-23"},
        {"2023", "43", "2023-10-23", "2023-10-30"},
        {"2023", "44", "2023-10-30", "2023-11-06"}
      ]

      weeks = AdminTools.generate_iso_weeks(~D[2023-10-02], ~D[2023-10-30])

      assert weeks == expected_weeks
    end
  end
end
