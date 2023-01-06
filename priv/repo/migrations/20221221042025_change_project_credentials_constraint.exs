defmodule Lightning.Repo.Migrations.ChangeProjectCredentialsConstraint do
  use Ecto.Migration

  def change do
    alter table(:project_credentials) do
      modify :credential_id, references(:credentials, on_delete: :delete_all, type: :binary_id),
        from: references(:credentials, on_delete: :nothing, type: :binary_id)
    end

    drop(constraint(:credentials_audit, "credentials_audit_row_id_fkey"))
  end
end
