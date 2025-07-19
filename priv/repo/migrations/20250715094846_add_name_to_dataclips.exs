defmodule Lightning.Repo.Migrations.AddNameToDataclips do
  use Ecto.Migration

  def change do
    alter table("dataclips") do
      add :name, :string
    end

    create unique_index("dataclips", [:name, :project_id])
    create index("dataclips", [:name])
  end
end
