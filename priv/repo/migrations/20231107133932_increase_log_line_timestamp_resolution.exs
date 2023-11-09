defmodule Lightning.Repo.Migrations.IncreaseLogLineTimestampResolution do
  use Ecto.Migration

  def change do
    alter table(:log_lines) do
      modify :timestamp, :utc_datetime_usec
    end
  end
end
