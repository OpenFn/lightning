defmodule Lightning.Repo.Migrations.ChangeCredentialsAuditToAuditEvents do
  use Ecto.Migration

  def up do
    rename_index(from: "credentials_audit_pkey", to: "audit_events_pkey")
    rename_index(from: "credentials_audit_row_id_index", to: "audit_events_item_id_index")
    drop constraint("credentials_audit", "credentials_audit_actor_id_fkey")

    rename table("credentials_audit"), :row_id, to: :item_id
    rename table("credentials_audit"), :metadata, to: :changes
    create index("credentials_audit", [:actor_id])

    rename table(:credentials_audit), to: table(:audit_events)

    alter table("audit_events") do
      add :item_type, :string, default: "credential"
    end
  end

  defp rename_index(from: from, to: to) do
    execute(
      """
      ALTER INDEX #{from} RENAME TO #{to};
      """,
      """
      ALTER INDEX #{to} RENAME TO #{from};
      """
    )
  end
end
