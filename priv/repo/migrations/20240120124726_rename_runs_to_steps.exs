defmodule Lightning.Repo.Migrations.RenameRunsToSteps do
  use Ecto.Migration

  def up do
    execute "update dataclips set \"type\" = 'step_result' where \"type\" = 'run_result';"
    rename table("runs"), to: table("steps")

    rename table("attempt_runs"), to: table("attempt_steps")
    rename table("attempt_steps"), :run_id, to: :step_id

    rename table("log_lines"), :run_id, to: :step_id
  end

  def down do
    rename table("log_lines"), :step_id, to: :run_id

    rename table("attempt_steps"), :step_id, to: :run_id
    rename table("attempt_steps"), to: table("attempt_runs")

    rename table("steps"), to: table("runs")
    execute "update dataclips set \"type\" = 'run_result' where \"type\" = 'step_result';"
  end
end
