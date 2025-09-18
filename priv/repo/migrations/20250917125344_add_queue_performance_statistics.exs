defmodule Lightning.Repo.Migrations.AddQueuePerformanceStatistics do
  use Ecto.Migration

  def up do
    # Help planner understand correlation between workflow concurrency and run distribution
    execute """
    CREATE STATISTICS stats_workflow_concurrency_distribution (ndistinct, dependencies)
    ON project_id, concurrency FROM workflows
    """

    # Help with the round-robin project_id parameter estimation
    execute """
    CREATE STATISTICS stats_project_distribution (ndistinct)
    ON project_id, id FROM workflows
    """

    # For runs table queue operations
    execute """
    CREATE STATISTICS stats_runs_queue_eligibility (ndistinct, dependencies)
    ON state, inserted_at, priority FROM runs
    """

    # Update table statistics
    execute "ANALYZE runs"
    execute "ANALYZE workflows"
  end

  def down do
    execute "DROP STATISTICS IF EXISTS stats_workflow_concurrency_distribution"
    execute "DROP STATISTICS IF EXISTS stats_project_distribution"
    execute "DROP STATISTICS IF EXISTS stats_runs_queue_eligibility"
  end
end
