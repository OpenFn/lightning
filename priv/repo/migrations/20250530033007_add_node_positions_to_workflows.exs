defmodule Lightning.Repo.Migrations.AddNodePositionsToWorkflows do
  use Ecto.Migration

  def change do
    alter table("workflows") do
      add :positions, :jsonb
    end
  end
end
