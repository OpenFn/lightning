defmodule Lightning.Repo.Migrations.AddUniqueIndexOnProjectUsers do
  use Ecto.Migration

  def change do
    create unique_index("project_users", [:project_id],
             where: "role = 'owner'",
             name: "project_owner_unique_index"
           )
  end
end
