defmodule Lightning.Repo.Migrations.AddAttemptPriority do
  use Ecto.Migration

  def change do
    alter table(:attempts) do
      add :priority, :integer, null: false, default: 1
    end
  end
end
