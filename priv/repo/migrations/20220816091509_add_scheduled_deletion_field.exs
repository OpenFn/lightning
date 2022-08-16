defmodule Lightning.Repo.Migrations.AddScheduledDeletionField do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:scheduled_deletion, :utc_datetime)
    end
  end
end
