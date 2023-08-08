defmodule Lightning.Repo.Migrations.RemoveTargetId do
  use Ecto.Migration

  def change do
    alter table(:project_repo) do
      remove :target_id
    end
  end
end
