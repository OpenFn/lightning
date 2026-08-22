defmodule Lightning.Repo.Migrations.FixChannelSnapshotCascade do
  use Ecto.Migration

  def up do
    drop constraint(:channel_snapshots, "channel_snapshots_channel_id_fkey")

    alter table(:channel_snapshots) do
      modify :channel_id,
             references(:channels, type: :binary_id, on_delete: :delete_all),
             null: false
    end
  end

  def down do
    drop constraint(:channel_snapshots, "channel_snapshots_channel_id_fkey")

    alter table(:channel_snapshots) do
      modify :channel_id,
             references(:channels, type: :binary_id, on_delete: :restrict),
             null: false
    end
  end
end
