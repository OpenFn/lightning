defmodule Lightning.Repo.Migrations.AddAttemptsTable do
  use Ecto.Migration

  def change do
    create table(:attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :reason_id, references(:invocation_reasons, on_delete: :nothing, type: :binary_id),
        null: false

      add :work_order_id, references(:work_orders, on_delete: :delete_all, type: :binary_id),
        null: false

      timestamps()
    end

    create index(:attempts, [:work_order_id])
  end
end
