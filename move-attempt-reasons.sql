WITH flat_attempts AS (
  SELECT a.id,
    ir.type,
    ir.trigger_id AS starting_trigger_id,
    CASE
      WHEN ir.trigger_id IS NULL THEN r.job_id
      ELSE NULL
    END AS starting_job_id,
    ir.dataclip_id
  FROM attempts a
    JOIN invocation_reasons ir ON ir.id = a.reason_id
    LEFT JOIN (
      SELECT DISTINCT ON (attempt_id) attempt_id,
        run_id
      FROM attempt_runs
      ORDER BY attempt_id,
        inserted_at ASC
    ) AS ar
    LEFT JOIN runs r ON r.id = ar.run_id ON a.id = ar.attempt_id
)
UPDATE attempts
SET starting_trigger_id = flat_attempts.starting_trigger_id,
  starting_job_id = flat_attempts.starting_job_id,
  dataclip_id = flat_attempts.dataclip_id
FROM flat_attempts
WHERE attempts.id = flat_attempts.id;