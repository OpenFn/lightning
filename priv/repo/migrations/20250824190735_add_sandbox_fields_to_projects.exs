defmodule Lightning.Repo.Migrations.AddSandboxFieldsToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects, primary_key: false) do
      add :parent_id, references(:projects, type: :binary_id, on_delete: :nilify_all)
      add :color, :string
      add :env, :string
      add :version_history, {:array, :string}, default: [], null: false
    end

    create index(:projects, [:parent_id])

    create unique_index(:projects, [:parent_id, :name],
             where: "parent_id IS NOT NULL",
             name: "projects_unique_child_name"
           )

    create constraint(:projects, :parent_not_self, check: "parent_id IS NULL OR parent_id <> id")
  end
end
