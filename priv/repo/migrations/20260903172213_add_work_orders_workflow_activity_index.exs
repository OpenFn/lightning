defmodule Lightning.Repo.Migrations.AddWorkOrdersWorkflowActivityIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # Composite index for the workflow health page. Both endpoints filter on
    # `workflow_id` and a `last_activity` window; the existing single-column
    # indexes make the planner pick one and heap-filter the rest, which degrades
    # with total volume rather than with the size of the answer.
    create index(:work_orders, [:workflow_id, :last_activity], concurrently: true)
  end
end
