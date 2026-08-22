defmodule Lightning.Repo.Migrations.RenameChannelSourceSinkToClientDestination do
  use Ecto.Migration

  def change do
    # --- channels: rename sink_url → destination_url ---
    rename table(:channels), :sink_url, to: :destination_url

    # --- channel_snapshots: rename sink_url → destination_url ---
    # Note: sink_project_credential_id and sink_credential_name columns
    # don't exist in the DB (defined in original migration but never created).
    rename table(:channel_snapshots), :sink_url, to: :destination_url

    # --- channel_auth_methods: update role enum values ---
    # Role is stored as a plain string column, so a direct UPDATE works.
    # Existing unique indexes on (channel_id, role, fk_id) update automatically.
    execute(
      "UPDATE channel_auth_methods SET role = 'client' WHERE role = 'source'",
      "UPDATE channel_auth_methods SET role = 'source' WHERE role = 'client'"
    )

    execute(
      "UPDATE channel_auth_methods SET role = 'destination' WHERE role = 'sink'",
      "UPDATE channel_auth_methods SET role = 'sink' WHERE role = 'destination'"
    )

    # --- channel_events: rename type enum value ---
    execute(
      "UPDATE channel_events SET type = 'destination_response' WHERE type = 'sink_response'",
      "UPDATE channel_events SET type = 'sink_response' WHERE type = 'destination_response'"
    )

    # --- Partial unique index: at-most-one destination auth method per channel ---
    create unique_index(
             :channel_auth_methods,
             [:channel_id],
             where: "role = 'destination'",
             name: :channel_auth_methods_destination_unique
           )
  end
end
