defmodule Lightning.Repo.Migrations.AddDataRetentionSettingToProjects do
  use Ecto.Migration

  def change do
    alter table("projects") do
      add :data_retention_policy, :string, default: "retain_all"
    end
  end
end
