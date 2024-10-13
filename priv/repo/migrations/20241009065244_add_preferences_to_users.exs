defmodule Lightning.Repo.Migrations.AddPreferencesToUsers do
  use Ecto.Migration

  def change do
    alter table("users") do
      add :preferences, :jsonb, default: fragment("jsonb_object('{}')"), null: false
    end
  end
end
