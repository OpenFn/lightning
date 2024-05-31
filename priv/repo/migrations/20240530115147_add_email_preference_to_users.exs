defmodule Lightning.Repo.Migrations.AddContactPreferenceToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :contact_preference, :string, default: "critical"
    end
  end
end
