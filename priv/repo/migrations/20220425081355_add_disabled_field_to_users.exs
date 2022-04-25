defmodule Lightning.Repo.Migrations.AddDisabledFieldToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :disabled, :boolean, default: false
    end
  end
end
