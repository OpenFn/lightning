defmodule Lightning.Repo.Migrations.CreateConnectedSystems do
  use Ecto.Migration

  def change do
    create table(:connected_systems, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :name, :string, null: false
      add :slug, :string, null: false
      add :type, :string
      add :description, :text
      add :docs_url, :string
      add :contact, :string
      add :access_instructions, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:connected_systems, [:name],
             name: :connected_systems_name_index
           )

    create unique_index(:connected_systems, [:slug],
             name: :connected_systems_slug_index
           )
  end
end
