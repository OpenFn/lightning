defmodule Lightning.Repo.Migrations.FixInconsistentDataclipRetentionPeriods do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE projects
    SET dataclip_retention_period = history_retention_period
    WHERE dataclip_retention_period > history_retention_period
    """)
  end

  def down do
    :ok
  end
end
