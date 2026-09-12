defmodule Lightning.Repo.Migrations.CreateWorkflowReleases do
  use Ecto.Migration

  def change do
    create table(:workflow_releases, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :version_number, :integer, null: false
      add :kind, :string, null: false

      add :workflow_id,
          references(:workflows, type: :binary_id, on_delete: :delete_all),
          null: false

      # A release must always resolve to real content, so its snapshot is never
      # allowed to disappear out from under it.
      add :snapshot_id,
          references(:workflow_snapshots, type: :binary_id, on_delete: :restrict),
          null: false

      # Null for backfilled go-live releases (no known actor).
      add :published_by_id,
          references(:users, type: :binary_id, on_delete: :nilify_all),
          null: true

      # The sandbox a promote came from; null for a go-live.
      add :source_project_id,
          references(:projects, type: :binary_id, on_delete: :nilify_all),
          null: true

      timestamps(type: :utc_datetime_usec, updated_at: false, null: false)
    end

    create unique_index(:workflow_releases, [:workflow_id, :version_number])
    create index(:workflow_releases, [:snapshot_id])
    create index(:workflow_releases, [:published_by_id])
    create index(:workflow_releases, [:source_project_id])
  end
end
