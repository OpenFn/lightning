defmodule Lightning.Repo.Migrations.ReSnapshotCronCursorJobId do
  @moduledoc """
  Creates new snapshots for workflows with cron triggers that have a
  cron_cursor_job_id set.

  The previous migration added cron_cursor_job_id to triggers and backfilled
  it, but existing snapshots were created before that column existed. Since
  runs execute against snapshots, the cron_cursor_job_id was effectively
  invisible at runtime until a new snapshot is captured.
  """
  use Ecto.Migration

  import Ecto.Query

  def up do
    alias Lightning.Workflows.Workflow
    alias Lightning.Workflows.Snapshot

    workflow_ids =
      from(t in Lightning.Workflows.Trigger,
        where: t.type == :cron and not is_nil(t.cron_cursor_job_id),
        select: t.workflow_id
      )
      |> repo().all()
      |> Enum.uniq()

    for workflow_id <- workflow_ids do
      workflow =
        from(w in Workflow, where: w.id == ^workflow_id)
        |> repo().one!()

      workflow
      |> Workflow.touch()
      |> repo().update!()
      |> Snapshot.create()
    end
  end

  def down do
    :ok
  end
end
