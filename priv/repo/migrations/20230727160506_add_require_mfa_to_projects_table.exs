defmodule Lightning.Repo.Migrations.AddRequireMfaToProjectsTable do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :requires_mfa, :boolean, default: false
    end
  end
end
