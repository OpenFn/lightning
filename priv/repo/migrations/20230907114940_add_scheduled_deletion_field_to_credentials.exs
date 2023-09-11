defmodule Lightning.Repo.Migrations.AddScheduledDeletionFieldToCredentials do
  use Ecto.Migration

  def change do
    alter table(:credentials) do
      add(:scheduled_deletion, :utc_datetime)
    end
  end
end
