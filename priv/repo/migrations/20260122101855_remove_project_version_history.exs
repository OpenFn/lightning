defmodule Lightning.Repo.Migrations.RemoveProjectVersionHistory do
  use Ecto.Migration

  def up do
    alter table(:projects) do
      remove :version_history
    end
  end

  def down do
    alter table(:projects) do
      add :version_history, {:array, :string}, default: []
    end
  end
end
