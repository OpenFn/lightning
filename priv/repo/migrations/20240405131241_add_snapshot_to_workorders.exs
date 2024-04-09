defmodule Lightning.Repo.Migrations.AddSnapshotToWorkorders do
  use Ecto.Migration

  def change do
    alter table(:work_orders) do
      add :snapshot_id,
          references(:workflow_snapshots, on_delete: :delete_all, type: :binary_id),
          null: true
    end

    alter table(:runs) do
      add :snapshot_id,
          references(:workflow_snapshots, on_delete: :delete_all, type: :binary_id),
          null: true
    end
  end
end
