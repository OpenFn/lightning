defmodule Lightning.Repo.Migrations.ChangeSnapshotFkConstraintsToRestrict do
  use Ecto.Migration

  def up do
    # Drop existing foreign key constraints
    drop constraint(:work_orders, "work_orders_snapshot_id_fkey")
    drop constraint(:runs, "runs_snapshot_id_fkey")
    drop constraint(:steps, "steps_snapshot_id_fkey")

    # Re-add with RESTRICT instead of CASCADE
    alter table(:work_orders) do
      modify :snapshot_id,
             references(:workflow_snapshots, on_delete: :restrict, type: :binary_id),
             null: true
    end

    alter table(:runs) do
      modify :snapshot_id,
             references(:workflow_snapshots, on_delete: :restrict, type: :binary_id),
             null: true
    end

    alter table(:steps) do
      modify :snapshot_id,
             references(:workflow_snapshots, on_delete: :restrict, type: :binary_id),
             null: true
    end
  end

  def down do
    # Drop RESTRICT constraints
    drop constraint(:work_orders, "work_orders_snapshot_id_fkey")
    drop constraint(:runs, "runs_snapshot_id_fkey")
    drop constraint(:steps, "steps_snapshot_id_fkey")

    # Re-add original CASCADE constraints
    alter table(:work_orders) do
      modify :snapshot_id,
             references(:workflow_snapshots, on_delete: :delete_all, type: :binary_id),
             null: true
    end

    alter table(:runs) do
      modify :snapshot_id,
             references(:workflow_snapshots, on_delete: :delete_all, type: :binary_id),
             null: true
    end

    alter table(:steps) do
      modify :snapshot_id,
             references(:workflow_snapshots, on_delete: :delete_all, type: :binary_id),
             null: true
    end
  end
end
