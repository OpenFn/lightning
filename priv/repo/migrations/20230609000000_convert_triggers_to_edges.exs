defmodule Lightning.Repo.Migrations.ConvertTriggersToEdges do
  use Ecto.Migration

  def up do
    execute("""
    WITH triggers_cte AS (
      SELECT
        t.workflow_id,
        t.type,
        CASE
          WHEN t.type IN ('cron', 'webhook') THEN NULL
          ELSE t.upstream_job_id
        END AS source_job_id,
        CASE
          WHEN t.type IN ('cron', 'webhook') THEN t.id
          ELSE NULL
        END AS source_trigger_id,
        j.id AS target_job_id,
        t.inserted_at,
        t.updated_at
      FROM triggers AS t
      LEFT JOIN jobs j ON j.trigger_id = t.id
    )

    INSERT INTO workflow_edges (
      id,
      workflow_id,
      source_job_id,
      source_trigger_id,
      target_job_id,
      condition,
      inserted_at,
      updated_at
    )
    SELECT
      gen_random_uuid(),
      cte.workflow_id,
      cte.source_job_id,
      cte.source_trigger_id,
      cte.target_job_id,
      CASE
        WHEN cte.type IN ('cron', 'webhook') THEN 'always'
        WHEN cte.type = 'on_job_success' THEN 'on_job_success'
        WHEN cte.type = 'on_job_failure' THEN 'on_job_failure'
      END,
      cte.inserted_at,
      cte.updated_at
    FROM triggers_cte AS cte
    """)

    execute("""
    update jobs set trigger_id = null
    """)

    execute("""
    delete from triggers where type in ('on_job_success', 'on_job_failure')
    """)
  end

  def down do
    # We do not support downgrading. Write you own down if needed.
  end
end
