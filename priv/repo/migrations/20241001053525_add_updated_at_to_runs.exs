defmodule Lightning.Repo.Migrations.AddUpdatedAtToRuns do
  use Ecto.Migration

  def change do
    alter table("runs") do
      add :updated_at, :utc_datetime_usec
    end

    execute(
      """
      WITH latest_step_updates AS (
          SELECT
              runs.id AS run_id,
              MAX(steps.updated_at) AS max_updated_at
          FROM
              runs
          LEFT JOIN
              run_steps ON runs.id = run_steps.run_id
          LEFT JOIN
              steps ON run_steps.step_id = steps.id
          GROUP BY
              runs.id
      )
      UPDATE runs
      SET updated_at = COALESCE(latest_step_updates.max_updated_at, runs.inserted_at)
      FROM latest_step_updates
      WHERE runs.id = latest_step_updates.run_id
      """,
      "SELECT true"
    )

    alter table("runs") do
      modify :updated_at, :utc_datetime_usec, null: false, from: {:utc_datetime_usec, null: true}
    end
  end
end
