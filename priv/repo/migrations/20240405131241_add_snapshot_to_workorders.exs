defmodule Lightning.Repo.Migrations.AddSnapshotToWorkorders do
  use Ecto.Migration

  def change do
    alter table(:work_orders) do
      add :snapshot_id,
          references(:workflow_snapshots, on_delete: :delete_all, type: :binary_id),
          null: true

      modify :trigger_id, :binary_id,
        null: true,
        from: {references(:triggers, type: :binary_id, on_delete: :nilify_all), null: false}
    end

    alter table(:runs) do
      add :snapshot_id,
          references(:workflow_snapshots, on_delete: :delete_all, type: :binary_id),
          null: true

      modify :starting_trigger_id, :binary_id,
        from: references(:triggers, type: :binary_id, on_delete: :delete_all)

      modify :starting_job_id, :binary_id,
        from: references(:jobs, type: :binary_id, on_delete: :delete_all)
    end

    alter table(:steps) do
      add :snapshot_id,
          references(:workflow_snapshots, on_delete: :delete_all, type: :binary_id),
          null: true

      modify :job_id, :binary_id,
        from: references(:jobs, type: :binary_id, on_delete: :delete_all)
    end
  end
end
