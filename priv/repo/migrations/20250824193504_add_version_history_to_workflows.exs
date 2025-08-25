defmodule Lightning.Repo.Migrations.AddVersionHistoryToWorkflows do
  use Ecto.Migration

  def change do
    alter table(:workflows, primary_key: false) do
      add :version_history, {:array, :string}, default: [], null: false
    end
  end
end
