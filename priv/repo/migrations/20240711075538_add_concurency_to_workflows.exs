defmodule Lightning.Repo.Migrations.AddConcurencyToWorkflows do
  use Ecto.Migration

  def change do
    alter table(:workflows) do
      add :concurrency, :integer, default: nil
    end
  end
end
