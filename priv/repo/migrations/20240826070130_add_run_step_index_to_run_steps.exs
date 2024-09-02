defmodule Lightning.Repo.Migrations.AddRunStepIndexToRunSteps do
  use Ecto.Migration

  def change do
    create index(:run_steps, [:run_id, :step_id])
  end
end
