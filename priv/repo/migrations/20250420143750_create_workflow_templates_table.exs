defmodule Lightning.Repo.Migrations.CreateWorkflowTemplatesTable do
  use Ecto.Migration

  def change do
    create table(:workflow_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text, null: true
      add :code, :text, null: false
      add :positions, :text, null: true
      add :tags, {:array, :string}, null: false

      add :workflow_id, references(:workflows, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create index(:workflow_templates, [:tags], using: :gin)
    create unique_index(:workflow_templates, [:workflow_id])
  end
end
