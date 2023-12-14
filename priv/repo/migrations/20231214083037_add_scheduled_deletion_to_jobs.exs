defmodule Lightning.Repo.Migrations.AddScheduledDeletionToJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add(:scheduled_deletion, :utc_datetime)
    end
  end
end
