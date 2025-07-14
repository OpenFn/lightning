defmodule Lightning.Repo.Migrations.AddNodePositionsToWorkflows do
  use Ecto.Migration

  def change do
    alter table("workflows") do
      add_if_not_exists :positions, :jsonb
    end

    alter table("workflow_templates") do
      remove :positions, :text
      add :positions, :jsonb
    end
  end
end
