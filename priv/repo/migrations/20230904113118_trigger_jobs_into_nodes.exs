defmodule Lightning.Repo.Migrations.TriggerJobsIntoNodes do
  use Ecto.Migration

  def change do
    alter table(:attempts) do
      add :starting_trigger_id, references(:triggers, type: :binary_id, on_delete: :delete_all),
        null: true

      add :starting_job_id, references(:jobs, type: :binary_id, on_delete: :delete_all),
        null: true

      add :dataclip_id, references(:dataclips, type: :binary_id, on_delete: :delete_all),
        null: true

      add :created_by_id, references(:users, type: :binary_id, on_delete: :delete_all), null: true
    end

    execute """
            WITH flat_attempts AS (
              SELECT a.id,
                ir.type,
                ir.trigger_id AS starting_trigger_id,
                CASE
                  WHEN ir.trigger_id IS NULL THEN r.job_id
                  ELSE NULL
                END AS starting_job_id,
                COALESCE(ir.dataclip_id, ir_runs.input_dataclip_id) as dataclip_id
              FROM attempts a
                JOIN invocation_reasons ir ON ir.id = a.reason_id
                LEFT JOIN runs ir_runs ON ir.run_id = ir_runs.id
                LEFT JOIN (
                  SELECT DISTINCT ON (attempt_id) attempt_id,
                    run_id
                  FROM attempt_runs
                  JOIN attempts ON attempts.id = attempt_runs.attempt_id
                  JOIN runs ON runs.id = attempt_runs.run_id
                  WHERE runs.inserted_at >= attempts.inserted_at
                  ORDER BY attempt_id,
                    attempt_runs.inserted_at ASC
                ) AS ar
                LEFT JOIN runs r ON r.id = ar.run_id ON a.id = ar.attempt_id
            )
            UPDATE attempts
            SET starting_trigger_id = flat_attempts.starting_trigger_id,
              starting_job_id = flat_attempts.starting_job_id,
              dataclip_id = flat_attempts.dataclip_id
            FROM flat_attempts
            WHERE attempts.id = flat_attempts.id;
            """,
            ""

    create(
      constraint(
        :attempts,
        :validate_job_or_trigger,
        check: "(starting_job_id IS NOT NULL) OR (starting_trigger_id IS NOT NULL)"
      )
    )

    alter table(:attempts) do
      modify :dataclip_id, :binary_id, null: false, from: {:binary_id, null: true}
      modify :reason_id, :binary_id, null: true, from: {:binary_id, null: false}
    end
  end
end
