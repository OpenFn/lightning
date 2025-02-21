defmodule Lightning.Repo.Migrations.AddProjectConcurrency do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :concurrency, :integer
    end
  end
end
