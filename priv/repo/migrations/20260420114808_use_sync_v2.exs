defmodule Lightning.Repo.Migrations.UseSyncV2 do
  use Ecto.Migration

  def change do
    alter table(:project_repo_connections) do
      add :sync_version, :boolean, null: false, default: false
    end
  end
end
