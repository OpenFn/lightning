defmodule Lightning.Repo.Migrations.AddFailureAlertToProjectUsers do
  use Ecto.Migration

  def change do
    alter table(:project_users) do
      add :failure_alert, :boolean, default: true
    end
  end
end
