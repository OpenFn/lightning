defmodule Lightning.Repo.Migrations.UsecTimestampsFix do
  use Ecto.Migration

  def change do
    for table_name <- [:runs, :dataclips, :attempts, :attempt_runs] do
      alter table(table_name) do
        modify :inserted_at, :naive_datetime_usec, from: :naive_datetime
        modify :updated_at, :naive_datetime_usec, from: :naive_datetime
      end
    end
  end
end
