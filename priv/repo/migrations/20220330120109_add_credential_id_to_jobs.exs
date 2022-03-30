defmodule Lightning.Repo.Migrations.AddCredentialIdToJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add :credential_id, references(:credentials, type: :binary_id)
    end
  end
end
