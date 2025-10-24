defmodule Lightning.Repo.Migrations.AddKeychainCredentialToJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add :keychain_credential_id,
          references(:keychain_credentials, on_delete: :nilify_all, type: :binary_id)
    end

    create index(:jobs, [:keychain_credential_id])

    # Check constraint to ensure only one credential type is set
    create constraint(:jobs, :credential_exclusivity,
             check:
               "NOT (project_credential_id IS NOT NULL AND keychain_credential_id IS NOT NULL)"
           )
  end
end
