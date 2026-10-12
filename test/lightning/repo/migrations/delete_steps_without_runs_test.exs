defmodule Lightning.Repo.Migrations.DeleteStepsWithoutRunsTest do
  use Lightning.DataCase, async: false

  import Lightning.Factories

  alias Lightning.Invocation.Step
  alias Lightning.Repo
  alias Lightning.Repo.Migrations.DeleteStepsWithoutRuns

  @migration "priv/repo/migrations/20261012115406_delete_steps_without_runs.exs"

  # Run under a version that is never recorded, so the migrator doesn't skip
  # it as already applied.
  @version 99_999_999_999_999

  test "deletes steps without runs and leaves linked steps alone" do
    # `mix test` has already loaded it if it migrated the test database.
    unless Code.ensure_loaded?(DeleteStepsWithoutRuns),
      do: Code.require_file(@migration)

    %{triggers: [trigger], jobs: [job | _]} =
      workflow = insert(:simple_workflow)

    linked =
      for _ <- 1..3 do
        step = insert(:step, job: job)

        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          runs: [
            build(:run,
              starting_trigger: trigger,
              dataclip: build(:dataclip),
              steps: [step]
            )
          ]
        )

        step
      end

    orphans = for _ <- 1..2_500, do: insert(:step, job: job)

    assert :ok =
             Ecto.Migrator.up(Repo, @version, DeleteStepsWithoutRuns, log: false)

    for step <- linked, do: assert(Repo.get(Step, step.id))

    orphan_ids = Enum.map(orphans, & &1.id)

    assert Repo.aggregate(from(s in Step, where: s.id in ^orphan_ids), :count) ==
             0
  end
end
