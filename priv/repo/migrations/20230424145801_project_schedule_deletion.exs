defmodule Lightning.Repo.Migrations.ProjectScheduleDeletion do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add(:scheduled_deletion, :utc_datetime)
    end
  end
end
