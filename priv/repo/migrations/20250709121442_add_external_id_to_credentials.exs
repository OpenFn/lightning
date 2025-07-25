defmodule Lightning.Repo.Migrations.AddExternalIdToCredentials do
  use Ecto.Migration

  def change do
    alter table(:credentials) do
      add :external_id, :string
    end

    create index(:credentials, [:external_id])
  end
end
