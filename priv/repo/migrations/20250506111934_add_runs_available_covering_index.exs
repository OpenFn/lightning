defmodule Lightning.Repo.Migrations.AddRunsAvailableCoveringIndex do
  use Ecto.Migration

  def change do
    # TODO - confirm that we have all these...
    # create index(:work_orders, [:snapshot_id])
    # create index(:workflows, [:project_id])
    # create index(:runs, [:state, :inserted_at])
    # create index(:runs, [:work_order_id])
    # create index(:work_orders, [:workflow_id, :project_id])

    create index(:runs, [:state, :inserted_at],
             include: [:work_order_id],
             where: "state = 'available'",
             name: :runs_available_covering_idx
           )
  end
end
