defmodule Lightning.Repo.Migrations.AddStateColumnToWorkorders do
  use Ecto.Migration

  def change do
    alter table(:work_orders) do
      add :state, :string, null: false
    end
  end
end
