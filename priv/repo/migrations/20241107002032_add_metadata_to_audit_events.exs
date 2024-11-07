defmodule Lightning.Repo.Migrations.AddMetadataToAuditEvents do
  use Ecto.Migration

  def change do
    alter table(:audit_events) do
      add :metadata, :map
    end
  end
end
