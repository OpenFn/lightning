defmodule Lightning.Repo.Migrations.AddIndexesToRunSteps do
  use Ecto.Migration

  def change do
    create_if_not_exists index("run_steps", [:step_id])
  end
end
