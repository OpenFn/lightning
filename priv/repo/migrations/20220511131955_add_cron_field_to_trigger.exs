defmodule Lightning.Repo.Migrations.AddCronFieldToTrigger do
  use Ecto.Migration

  def change do
    alter table(:triggers) do
      add :cron_expression, :string, default: nil, null: true
    end
  end
end
