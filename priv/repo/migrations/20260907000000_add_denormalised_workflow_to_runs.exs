defmodule Lightning.Repo.Migrations.AddDenormalisedWorkflowToRuns do
  use Ecto.Migration

  # EXPERIMENTAL (load-testing): denormalise workflow_id and project_id onto the
  # runs table so the claim query can avoid joining work_order -> workflow ->
  # project across the full active-run set.
  #
  # These are deliberately bare UUID columns with NO database-level FK, mirroring
  # the existing starting_job_id / starting_trigger_id precedent on this table
  # (see lib/lightning/runs/run.ex and issue #4538). They are nullable because
  # only the webhook ingress path (and its retries) populates them.
  def change do
    alter table(:runs) do
      add :workflow_id, :binary_id
    end
  end
end
