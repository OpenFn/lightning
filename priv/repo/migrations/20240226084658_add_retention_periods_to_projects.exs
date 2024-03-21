defmodule Lightning.Repo.Migrations.AddRetentionPeriodsToProjects do
  use Ecto.Migration

  def change do
    alter table("projects") do
      add :history_retention_period, :integer
      add :dataclip_retention_period, :integer
    end
  end
end
