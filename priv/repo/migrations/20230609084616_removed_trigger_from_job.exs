defmodule Lightning.Repo.Migrations.RemovedTriggerFromJob do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      remove :trigger_id
    end
  end
end
