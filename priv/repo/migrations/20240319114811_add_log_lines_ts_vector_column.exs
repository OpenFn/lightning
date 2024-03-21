defmodule Lightning.Repo.Migrations.AddLogLinesTSVectorColumn do
  use Ecto.Migration

  def change do
    alter table(:log_lines) do
      add :search_vector, :tsvector, null: true
    end
  end
end
