defmodule Lightning.AdminTools do
  def generate_iso_weeks(start_date, end_date) do
    Date.range(start_date, end_date)
    |> Enum.with_index()
    |> Enum.filter(fn {_date, i} ->
      rem(i, 7) == 0
    end)
    |> Enum.map(fn {date, _i} ->
      weeknum = Timex.format!(date, "{Wiso}")
      year = Timex.format!(date, "{WYYYY}")
      monday = Timex.parse!("#{year}-#{weeknum}", "{YYYY}-{Wiso}")

      {
        year,
        weeknum,
        monday |> Date.to_string(),
        monday |> Timex.shift(weeks: 1) |> Date.to_string()
      }
    end)
  end
end
