defmodule Lightning.Repo.Migrations.AddAdaptorCatalogueIndexes do
  use Ecto.Migration

  def change do
    create index(:adaptors, [:updated_at])
    create index(:adaptor_versions, [:inserted_at])
  end
end
