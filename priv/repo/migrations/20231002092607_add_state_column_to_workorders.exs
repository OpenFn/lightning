defmodule Lightning.Repo.Migrations.AddStateColumnToWorkorders do
  use Ecto.Migration

  def change do
    alter table(:work_orders) do
      add :state, :string, length: 10, default: "pending", null: false

      add :last_activity, :utc_datetime_usec
    end

    create index(:work_orders, [:state])

    import Ecto.Query

    execute(
      fn ->
        repo().update_all(
          from(a in "work_orders",
            update: [
              set: [state: "success", last_activity: a.updated_at]
            ]
          ),
          []
        )
      end,
      ""
    )
  end
end
