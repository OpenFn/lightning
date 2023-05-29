defmodule Lightning.Repo.Migrations.RemoveLogColumnFromRuns do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      remove :log
    end
  end
end
