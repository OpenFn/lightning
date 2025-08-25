defmodule Lightning.Repo.Migrations.CreateWorkflowVersions do
  use Ecto.Migration

  def change do
    create table(:workflow_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :hash, :string, null: false
      add :source, :string, null: false

      add :workflow_id,
          references(:workflows, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec, updated_at: false, null: false)
    end

    create unique_index(:workflow_versions, [:workflow_id, :hash])

    create index(:workflow_versions, [:workflow_id, :inserted_at, :id],
             name: :workflow_versions_latest_per_wf
           )

    create constraint(
             :workflow_versions,
             :hash_is_12_hex,
             check: "hash ~ '^[a-f0-9]{12}$'"
           )

    create constraint(
             :workflow_versions,
             :source_is_known,
             check: "source IN ('app','cli')"
           )
  end
end
