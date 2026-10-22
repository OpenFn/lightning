defmodule Lightning.Repo.Migrations.EnqueueDeleteOrphanedSteps do
  use Ecto.Migration

  # Plain SQL so this migration keeps working if the worker is ever renamed.
  # The job is scheduled two hours out so it runs after the last retention
  # sweep (every two hours) that a node on the previous release could still
  # make, catching any steps that sweep leaves behind.
  def up do
    execute("""
    INSERT INTO oban_jobs (state, queue, worker, args, max_attempts, scheduled_at)
    SELECT 'scheduled', 'maintenance', 'Lightning.Invocation.DeleteOrphanedSteps',
           '{}', 5, timezone('UTC', now()) + interval '2 hours'
    WHERE EXISTS (SELECT 1 FROM steps)
    """)
  end

  def down do
    execute("""
    DELETE FROM oban_jobs
    WHERE worker = 'Lightning.Invocation.DeleteOrphanedSteps'
      AND state IN ('available', 'scheduled')
    """)
  end
end
