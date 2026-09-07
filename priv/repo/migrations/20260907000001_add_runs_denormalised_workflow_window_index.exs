defmodule Lightning.Repo.Migrations.AddRunsDenormalisedWorkflowWindowIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # EXPERIMENTAL (load-testing): supports the rewritten workflow_limited_runs/1
  # window. Column order (workflow_id, priority, inserted_at) matches the
  # PARTITION BY / ORDER BY so the planner *may* feed the WindowAgg pre-sorted
  # and skip an explicit Sort. The partial predicate matches Run.active_states().
  #
  # INCLUDE (id) makes the index covering for an index-only scan -- but ONLY if
  # the ranking subquery projects nothing from `runs` beyond the key columns and
  # id. Tranche 3 is written to honour this: project_id is sourced from the
  # post-limit workflows join (workflows.project_id), and the window's `state`
  # copy is dropped (the final availability filter uses the outer Run.state), so
  # neither reaches this scan.
  #
  # Caveat: index-only scans need all-visible heap pages. On this churn-heavy
  # table active runs are frequently just-modified, so expect Heap Fetches > 0
  # and possibly a planner that skips the index under the low-selectivity
  # predicate. Kept in to confirm via EXPLAIN (ANALYZE, BUFFERS).
  def up do
    execute("""
      CREATE INDEX CONCURRENTLY runs_workflow_active_window_idx
      ON runs (workflow_id, priority, inserted_at) INCLUDE (id)
      WHERE state IN ('available', 'claimed', 'started');
    """)
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS runs_workflow_active_window_idx;")
  end
end
