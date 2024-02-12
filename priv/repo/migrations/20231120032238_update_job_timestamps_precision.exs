defmodule Lightning.Repo.Migrations.UpdateJobTimestampsPrecision do
  use Ecto.Migration

  def up do
    alter table(:jobs) do
      modify :inserted_at, :naive_datetime_usec
      modify :updated_at, :naive_datetime_usec
    end
  end

  def down do
    alter table(:jobs) do
      modify :inserted_at, :naive_datetime
      modify :updated_at, :naive_datetime
    end
  end
end
