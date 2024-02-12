defmodule Lightning.Repo.Migrations.RenameLogLinesPartitionsConstraintsAndFks do
  use Ecto.Migration

  def up do
    Enum.each(1..100, fn int ->
      execute("
      ALTER INDEX public.log_lines_#{int}_run_id_idx RENAME TO log_lines_#{int}_step_id_idx;
      ")

      execute("
      ALTER TABLE public.log_lines_#{int} RENAME CONSTRAINT log_lines_run_id_fkey TO log_lines_step_id_fkey;
      ")
    end)
  end

  def down do
    Enum.each(1..100, fn int ->
      execute("
      ALTER INDEX public.log_lines_#{int}_step_id_idx RENAME TO log_lines_#{int}_run_id_idx;
      ")

      execute("
      ALTER TABLE public.log_lines_#{int} RENAME CONSTRAINT log_lines_step_id_fkey TO log_lines_run_id_fkey;
      ")
    end)
  end
end
