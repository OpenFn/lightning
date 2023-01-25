defmodule Lightning.Repo.Migrations.AddDeletedAtToWorkflows do
  use Ecto.Migration

  def change do
    alter table(:workflows) do
      add(:deleted_at, :naive_datetime, null: true)
    end
  end
end
