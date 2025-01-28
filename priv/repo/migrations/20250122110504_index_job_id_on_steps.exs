defmodule Lightning.Repo.Migrations.IndexJobIdOnSteps do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:steps, [:job_id])
  end
end
