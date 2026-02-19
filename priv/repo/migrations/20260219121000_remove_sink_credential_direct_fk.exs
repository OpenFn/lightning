defmodule Lightning.Repo.Migrations.RemoveSinkCredentialDirectFk do
  use Ecto.Migration

  def change do
    alter table(:channels) do
      remove :sink_project_credential_id, references(:project_credentials)
    end

    alter table(:channel_snapshots) do
      remove :sink_project_credential_id, :binary_id
      remove :sink_credential_name, :string
    end
  end
end
