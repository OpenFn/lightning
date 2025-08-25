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

    # Sandbox names must be unique per parent; top-level projects may share names
    create unique_index(:projects, [:parent_id, :name],
             where: "parent_id IS NOT NULL",
             name: "projects_unique_child_name"
           )

    # Optional safety checks; validations will also exist in changesets
    create constraint(:projects, :color_must_be_hex,
             check: "color IS NULL OR color ~ '^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3}|[A-Fa-f0-9]{8})$'"
           )

    create constraint(:projects, :env_must_be_slug,
             check: "env IS NULL OR env ~ '^[a-z0-9][a-z0-9_-]{0,31}$'"
           )

    create constraint(:projects, :parent_not_self, check: "parent_id IS NULL OR parent_id <> id")
  end
end
