defmodule Lightning.Repo.Migrations.RenameAttemptsToRuns do
  use Ecto.Migration

  def up do
    rename table("attempts"), to: table("runs")
    rename table("attempt_steps"), to: table("run_steps")
    rename table("run_steps"), :attempt_id, to: :run_id
    rename table("log_lines"), :attempt_id, to: :run_id

    execute(
      "ALTER TABLE log_lines RENAME CONSTRAINT log_lines_attempt_id_fkey TO log_lines_run_id_fkey;"
    )

    execute("ALTER INDEX log_lines_attempt_id_index RENAME TO log_lines_run_id_index;")

    execute("ALTER TABLE run_steps RENAME CONSTRAINT attempt_steps_pkey TO run_steps_pkey;")

    execute(
      "ALTER TABLE run_steps RENAME CONSTRAINT attempt_steps_attempt_id_fkey TO run_steps_attempt_id_fkey;"
    )

    execute(
      "ALTER TABLE run_steps RENAME CONSTRAINT attempt_steps_step_id_fkey TO run_steps_step_id_fkey;"
    )

    execute("ALTER TABLE runs RENAME CONSTRAINT attempts_pkey TO runs_pkey;")

    execute(
      "ALTER TABLE runs RENAME CONSTRAINT attempts_created_by_id_fkey TO runs_created_by_id_fkey;"
    )

    execute(
      "ALTER TABLE runs RENAME CONSTRAINT attempts_dataclip_id_fkey TO runs_dataclip_id_fkey;"
    )

    execute(
      "ALTER TABLE runs RENAME CONSTRAINT attempts_starting_job_id_fkey TO runs_starting_job_id_fkey;"
    )

    execute(
      "ALTER TABLE runs RENAME CONSTRAINT attempts_starting_trigger_id_fkey TO runs_starting_trigger_id_fkey;"
    )

    execute(
      "ALTER TABLE runs RENAME CONSTRAINT attempts_work_order_id_fkey TO runs_work_order_id_fkey;"
    )

    execute("ALTER INDEX attempts_state_index RENAME TO runs_state_index;")
    execute("ALTER INDEX attempts_work_order_id_index RENAME TO runs_work_order_id_index;")
  end

  def down do
    execute("ALTER INDEX runs_work_order_id_index RENAME TO attempts_work_order_id_index;")
    execute("ALTER INDEX runs_state_index RENAME TO attempts_state_index;")

    execute(
      "ALTER TABLE runs RENAME CONSTRAINT runs_work_order_id_fkey TO attempts_work_order_id_fkey;"
    )

    execute(
      "ALTER TABLE runs RENAME CONSTRAINT runs_starting_trigger_id_fkey TO attempts_starting_trigger_id_fkey;"
    )

    execute(
      "ALTER TABLE runs RENAME CONSTRAINT runs_starting_job_id_fkey TO attempts_starting_job_id_fkey;"
    )

    execute(
      "ALTER TABLE runs RENAME CONSTRAINT runs_dataclip_id_fkey TO attempts_dataclip_id_fkey;"
    )

    execute(
      "ALTER TABLE runs RENAME CONSTRAINT runs_created_by_id_fkey TO attempts_created_by_id_fkey;"
    )

    execute("ALTER TABLE runs RENAME CONSTRAINT runs_pkey TO attempts_pkey;")

    execute(
      "ALTER TABLE run_steps RENAME CONSTRAINT run_steps_step_id_fkey TO attempt_steps_step_id_fkey;"
    )

    execute(
      "ALTER TABLE run_steps RENAME CONSTRAINT run_steps_attempt_id_fkey TO attempt_steps_attempt_id_fkey;"
    )

    execute("ALTER TABLE run_steps RENAME CONSTRAINT run_steps_pkey TO attempt_steps_pkey;")

    execute("ALTER INDEX log_lines_run_id_index RENAME TO log_lines_attempt_id_index;")

    execute(
      "ALTER TABLE log_lines RENAME CONSTRAINT log_lines_run_id_fkey TO log_lines_attempt_id_fkey;"
    )

    rename table("log_lines"), :run_id, to: :attempt_id
    rename table("run_steps"), :run_id, to: :attempt_id
    rename table("run_steps"), to: table("attempt_steps")
    rename table("runs"), to: table("attempts")
  end
end
