defmodule Lightning.Repo.Migrations.CreateWorkOrderLastActivityIndex do
  use Ecto.Migration

  def change do
    create index("work_orders", [:last_activity])
  end
end
