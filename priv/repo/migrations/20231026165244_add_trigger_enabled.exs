defmodule Lightning.Repo.Migrations.AddTriggerEnabled do
  use Ecto.Migration

  def change do
    alter table(:triggers) do
      add :enabled, :boolean, null: false, default: true
    end
  end
end
