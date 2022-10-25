defmodule Lightning.Repo.Migrations.AddWorkordersTable do
  use Ecto.Migration

  def change do
    create table(:work_orders, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workflow_id, references(:workflows, on_delete: :delete_all, type: :binary_id),
        null: false

      add :reason_id, references(:invocation_reasons, on_delete: :nothing, type: :binary_id),
        null: false

      timestamps()
    end

    create index(:work_orders, [:workflow_id])
    create index(:work_orders, [:reason_id])
  end
end
