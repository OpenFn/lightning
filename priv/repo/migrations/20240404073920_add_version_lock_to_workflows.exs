defmodule Lightning.Repo.Migrations.AddVersionLockToWorkflows do
  use Ecto.Migration

  def change do
    alter table(:workflows) do
      add :lock_version, :integer, default: 0, null: false
    end

    alter table(:workflow_snapshots) do
      add :lock_version, :integer, null: false
    end

    create index(:workflow_snapshots, [:workflow_id, "lock_version DESC"],
             unique: true,
             name: "workflow_snapshots_workflow_id_lock_version_index"
           )
  end
end
