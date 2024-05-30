defmodule Lightning.Repo.Migrations.AddEmailsPreferenceToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :emails_preference, :string, default: "critical"
    end
  end
end
