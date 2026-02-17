defmodule Lightning.Repo.Migrations.CreateChannelAuthMethods do
  use Ecto.Migration

  def change do
    # --- channel_auth_methods join table ---
    create table(:channel_auth_methods, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :channel_id,
          references(:channels, type: :binary_id, on_delete: :delete_all),
          null: false

      add :role, :string, null: false

      add :webhook_auth_method_id,
          references(:webhook_auth_methods,
            type: :binary_id,
            on_delete: :delete_all
          )

      add :project_credential_id,
          references(:project_credentials,
            type: :binary_id,
            on_delete: :delete_all
          )

      timestamps()
    end

    create index(:channel_auth_methods, [:channel_id])
    create index(:channel_auth_methods, [:webhook_auth_method_id])
    create index(:channel_auth_methods, [:project_credential_id])

    create unique_index(
             :channel_auth_methods,
             [:channel_id, :role, :webhook_auth_method_id],
             where: "webhook_auth_method_id IS NOT NULL",
             name: :channel_auth_methods_wam_unique
           )

    create unique_index(
             :channel_auth_methods,
             [:channel_id, :role, :project_credential_id],
             where: "project_credential_id IS NOT NULL",
             name: :channel_auth_methods_pc_unique
           )

    # --- Remove source credential FK from channels ---
    alter table(:channels) do
      remove :source_project_credential_id
    end
  end
end
