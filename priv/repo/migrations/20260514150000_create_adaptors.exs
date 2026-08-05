defmodule Lightning.Repo.Migrations.CreateAdaptors do
  use Ecto.Migration

  def change do
    create table(:adaptors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :source, :string, null: false, default: "npm"
      add :description, :text
      add :homepage, :string
      add :repository, :string
      add :license, :string
      add :latest_version, :string, null: false
      add :deprecated, :boolean, default: false, null: false
      add :schema_data, :map
      add :schema_sha256, :string
      add :icon_square_ext, :string
      add :icon_rectangle_ext, :string
      add :icon_square_sha256, :binary
      add :icon_rectangle_sha256, :binary
      add :checked_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, null: false)
    end

    create unique_index(:adaptors, [:name, :source])
    create index(:adaptors, [:source, :checked_at])

    create table(:adaptor_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :adaptor_id,
          references(:adaptors, type: :binary_id, on_delete: :delete_all),
          null: false

      add :version, :string, null: false
      add :integrity, :string
      add :tarball_url, :string
      add :size_bytes, :integer
      add :dependencies, :map
      add :peer_dependencies, :map
      add :published_at, :utc_datetime_usec
      add :deprecated, :boolean, default: false, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false, null: false)
    end

    create unique_index(:adaptor_versions, [:adaptor_id, :version])
  end
end
