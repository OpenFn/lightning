defmodule Lightning.Repo.Migrations.DropExitCode do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      remove :exit_code
    end
  end
end
