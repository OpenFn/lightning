defmodule Lightning.Repo.Migrations.AddAllowUnverifiedEmailToAuthProviders do
  use Ecto.Migration

  def change do
    alter table(:auth_providers) do
      add :allow_unverified_email, :boolean, null: false, default: false
    end
  end
end
