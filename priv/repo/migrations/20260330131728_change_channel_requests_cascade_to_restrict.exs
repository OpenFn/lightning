defmodule Lightning.Repo.Migrations.ChangeChannelRequestsCascadeToRestrict do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # Issue #4504: "channel_request is king" — channel_requests are the audit
  # record for channels. The FK to channels should use RESTRICT so that
  # deleting a channel cannot silently destroy its request history.
  #
  # This follows the same pattern as the runs-related cascade refactor
  # (#4538/b4f8dceea0) where runs/steps FKs were changed to RESTRICT.
  #
  # Uses NOT VALID + VALIDATE CONSTRAINT to avoid full table locks.

  def up do
    execute "ALTER TABLE channel_requests DROP CONSTRAINT channel_requests_channel_id_fkey"

    execute """
    ALTER TABLE channel_requests
      ADD CONSTRAINT channel_requests_channel_id_fkey
      FOREIGN KEY (channel_id) REFERENCES channels(id)
      ON DELETE RESTRICT
      NOT VALID
    """

    execute "ALTER TABLE channel_requests VALIDATE CONSTRAINT channel_requests_channel_id_fkey"
  end

  def down do
    execute "ALTER TABLE channel_requests DROP CONSTRAINT channel_requests_channel_id_fkey"

    execute """
    ALTER TABLE channel_requests
      ADD CONSTRAINT channel_requests_channel_id_fkey
      FOREIGN KEY (channel_id) REFERENCES channels(id)
      ON DELETE CASCADE
    """
  end
end
