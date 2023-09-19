defmodule Lightning.Repo.Migrations.RemoveDefauiltItemTypeForAuditEvents do
  use Ecto.Migration

  def change do
    alter table(:audit_events) do
      modify(:item_type, :string, default: nil, null: false)
    end
  end
end
