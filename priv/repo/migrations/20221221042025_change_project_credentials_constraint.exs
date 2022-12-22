defmodule Lightning.Repo.Migrations.ChangeProjectCredentialsConstraint do
  use Ecto.Migration

  def change do
    # drop constraint(:project_credentials, "project_credentials_credential_id_fkey")

    alter table(:project_credentials) do
      modify :credential_id, references(:credentials, on_delete: :delete_all, type: :binary_id), from: references(:credentials, on_delete: :nothing,  type: :binary_id)
    end


    # drop constraint(:credentials_audit, "credentials_audit_row_id_fkey")

    alter table(:credentials_audit) do
      modify :row_id, null: true, references(:credentials, on_delete: :nothing, type: :binary_id), from: references(:credentials, on_delete: :delete_all , type: :binary_id, null: false)
    end


  end
end
