defmodule Lightning.Repo.Migrations.EnqueueDeleteOrphanedStepsTest do
  use Lightning.DataCase, async: true

  import Ecto.Query

  alias Lightning.Repo

  @migration "priv/repo/migrations/20261012132048_enqueue_delete_orphaned_steps.exs"

  @worker "Lightning.Invocation.DeleteOrphanedSteps"

  test "enqueues one cleanup job on the maintenance queue, two hours out" do
    migrate()
    migrate()

    assert [job] = Repo.all(from(j in Oban.Job, where: j.worker == @worker))

    assert %{state: "scheduled", queue: "maintenance", args: %{}} = job

    assert job.worker ==
             Oban.Worker.to_string(Lightning.Invocation.DeleteOrphanedSteps)

    in_two_hours = DateTime.add(DateTime.utc_now(), 2, :hour)
    assert abs(DateTime.diff(job.scheduled_at, in_two_hours)) < 60
  end

  # Runs the INSERT read straight out of the migration file, so an edit to the
  # migration is an edit to what this tests.
  defp migrate do
    [_, sql] =
      Regex.run(
        ~r/execute\("""\n(\s*INSERT.*?)\n\s*"""\)/s,
        File.read!(@migration)
      )

    Repo.query!(sql)
  end
end
