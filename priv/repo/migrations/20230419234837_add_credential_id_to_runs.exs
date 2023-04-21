defmodule Lightning.Repo.Migrations.AddCredentialIdToRuns do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      add(:credential_id, references(:credentials, on_delete: :nothing, type: :binary_id),
        null: true
      )
    end
  end
end
