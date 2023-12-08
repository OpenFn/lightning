defmodule Lightning.Repo.Migrations.NaiveToUtcDatetimes do
  use Ecto.Migration

  def change do
    alter table(:user_backup_codes) do
      modify :used_at, :utc_datetime_usec
    end
  end
end
