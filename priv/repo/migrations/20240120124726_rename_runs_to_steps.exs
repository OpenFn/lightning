defmodule Lightning.Repo.Migrations.RenameRunsToSteps do
  use Ecto.Migration

  def up do
    rename table("runs"), to: table("steps")

    rename table("attempt_runs"), to: table("attempt_steps")
    rename table("attempt_steps"), :run_id, to: :step_id

    rename table("log_lines"), :run_id, to: :step_id

    execute("update dataclips set \"type\" = 'step_result' where \"type\" = 'run_result';")

    execute("ALTER TABLE steps RENAME CONSTRAINT runs_pkey TO steps_pkey;")

    execute(
      "ALTER TABLE steps RENAME CONSTRAINT runs_credential_id_fkey TO steps_credential_id_fkey;"
    )

    execute(
      "ALTER TABLE steps RENAME CONSTRAINT runs_input_dataclip_id_fkey TO steps_input_dataclip_id_fkey;"
    )

    execute("ALTER TABLE steps RENAME CONSTRAINT runs_job_id_fkey TO steps_job_id_fkey;")

    execute(
      "ALTER TABLE steps RENAME CONSTRAINT runs_output_dataclip_id_fkey TO steps_output_dataclip_id_fkey;"
    )

    execute(
      "ALTER TABLE attempt_steps RENAME CONSTRAINT attempt_runs_pkey TO attempt_steps_pkey;"
    )

    execute(
      "ALTER TABLE attempt_steps RENAME CONSTRAINT attempt_runs_attempt_id_fkey TO attempt_steps_attempt_id_fkey;"
    )

    execute(
      "ALTER TABLE attempt_steps RENAME CONSTRAINT attempt_runs_run_id_fkey TO attempt_steps_step_id_fkey;"
    )

    execute(
      "ALTER TABLE log_lines RENAME CONSTRAINT log_lines_run_id_fkey TO log_lines_step_id_fkey;"
    )

    execute("ALTER INDEX runs_exit_reason_index RENAME TO steps_exit_reason_index;")
    execute("ALTER INDEX log_lines_run_id_index RENAME TO log_lines_step_id_index;")
  end

  def down do
    execute("update dataclips set \"type\" = 'run_result' where \"type\" = 'step_result';")

    execute("ALTER TABLE steps RENAME CONSTRAINT steps_pkey TO runs_pkey;")

    execute(
      "ALTER TABLE steps RENAME CONSTRAINT steps_credential_id_fkey TO runs_credential_id_fkey;"
    )

    execute(
      "ALTER TABLE steps RENAME CONSTRAINT steps_input_dataclip_id_fkey TO runs_input_dataclip_id_fkey;"
    )

    execute("ALTER TABLE steps RENAME CONSTRAINT steps_job_id_fkey TO runs_job_id_fkey;")

    execute(
      "ALTER TABLE steps RENAME CONSTRAINT steps_output_dataclip_id_fkey TO runs_output_dataclip_id_fkey;"
    )

    execute(
      "ALTER TABLE attempt_steps RENAME CONSTRAINT attempt_steps_pkey TO attempt_runs_pkey;"
    )

    execute(
      "ALTER TABLE attempt_steps RENAME CONSTRAINT attempt_steps_attempt_id_fkey TO attempt_runs_attempt_id_fkey;"
    )

    execute(
      "ALTER TABLE attempt_steps RENAME CONSTRAINT attempt_steps_step_id_fkey TO attempt_runs_run_id_fkey;"
    )

    execute(
      "ALTER TABLE log_lines RENAME CONSTRAINT log_lines_step_id_fkey TO log_lines_run_id_fkey;"
    )

    execute("ALTER INDEX steps_exit_reason_index RENAME TO runs_exit_reason_index;")
    execute("ALTER INDEX log_lines_step_id_index RENAME TO log_lines_run_id_index;")

    rename table("log_lines"), :step_id, to: :run_id

    rename table("attempt_steps"), :step_id, to: :run_id
    rename table("attempt_steps"), to: table("attempt_runs")

    rename table("steps"), to: table("runs")
  end
end
