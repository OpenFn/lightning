defmodule Lightning.Repo.Migrations.UseSyncV2 do
  use Ecto.Migration

  def change do
    alter table(:project_repo_connections) do
      add :use_yaml_config, :boolean, null: false, default: false
    end
  end
end
