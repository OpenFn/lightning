defmodule Lightning.Repo.Migrations.AddWorkorderIdToAttempts do
  use Ecto.Migration

  def change do
    alter table(:attempts) do
      add :work_order_id, references(:work_orders, on_delete: :delete_all, type: :binary_id),
        null: false
    end

    create index(:attempts, [:work_order_id])
  end
end
