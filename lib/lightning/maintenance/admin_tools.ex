defmodule Lightning.AdminTools do
  def generate_iso_weeks(start_date, end_date) do
    Date.range(start_date, end_date)
    |> Enum.map(&Date.beginning_of_week(&1))
    |> Enum.uniq()
    |> Enum.map(fn date ->
      {year, week} = Timex.iso_week(date)

      {
        year |> Integer.to_string(),
        week |> Integer.to_string() |> String.pad_leading(2, "0"),
        date |> Date.to_string(),
        date |> Date.add(7) |> Date.to_string()
      }
    end)
  end
end
