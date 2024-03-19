defmodule Lightning.Repo.Migrations.DropUsageTrackingConfigurations do
  use Ecto.Migration

  def change do
    drop table(:usage_tracking_configurations)
  end
end
