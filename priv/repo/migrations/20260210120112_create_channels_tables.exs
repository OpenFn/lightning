defmodule Lightning.Repo.Migrations.CreateChannelsTables do
  use Ecto.Migration

  def change do
    # --- channels ---
    create table(:channels, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id,
          references(:projects, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false
      add :sink_url, :string, null: false

      add :source_project_credential_id,
          references(:project_credentials,
            type: :binary_id,
            on_delete: :nilify_all
          )

      add :sink_project_credential_id,
          references(:project_credentials,
            type: :binary_id,
            on_delete: :nilify_all
          )

      add :enabled, :boolean, null: false, default: true
      add :lock_version, :integer, null: false, default: 0

      timestamps()
    end

    create index(:channels, [:project_id])
    create index(:channels, [:source_project_credential_id])
    create index(:channels, [:sink_project_credential_id])
    create unique_index(:channels, [:project_id, :name])

    # --- channel_snapshots ---
    create table(:channel_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :channel_id,
          references(:channels, type: :binary_id, on_delete: :restrict),
          null: false

      add :lock_version, :integer, null: false
      add :name, :string, null: false
      add :sink_url, :string, null: false
      add :source_project_credential_id, :binary_id
      add :source_credential_name, :string
      add :sink_project_credential_id, :binary_id
      add :sink_credential_name, :string
      add :enabled, :boolean, null: false

      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:channel_snapshots, [:channel_id, :lock_version])
    create index(:channel_snapshots, [:channel_id])

    # --- channel_requests ---
    create table(:channel_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :channel_id,
          references(:channels, type: :binary_id, on_delete: :delete_all),
          null: false

      add :channel_snapshot_id,
          references(:channel_snapshots,
            type: :binary_id,
            on_delete: :restrict
          ),
          null: false

      add :request_id, :string, null: false
      add :client_identity, :string
      add :state, :string, null: false, default: "pending"
      add :started_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
    end

    create index(:channel_requests, [:channel_id])
    create index(:channel_requests, [:channel_id, :started_at])
    create index(:channel_requests, [:channel_snapshot_id])
    create index(:channel_requests, [:state])
    create unique_index(:channel_requests, [:request_id])

    # --- channel_events ---
    create table(:channel_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :channel_request_id,
          references(:channel_requests,
            type: :binary_id,
            on_delete: :delete_all
          ),
          null: false

      add :type, :string, null: false

      add :request_method, :string
      add :request_path, :string
      add :request_headers, :text
      add :request_body_preview, :text
      add :request_body_hash, :string, size: 64

      add :response_status, :smallint
      add :response_headers, :text
      add :response_body_preview, :text
      add :response_body_hash, :string, size: 64

      add :latency_ms, :integer
      add :error_message, :text

      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:channel_events, [:channel_request_id])
    create index(:channel_events, [:type])
  end
end
