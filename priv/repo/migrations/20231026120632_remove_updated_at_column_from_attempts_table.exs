defmodule Lightning.Repo.Migrations.RemoveUpdatedAtColumnFromAttemptsTable do
  use Ecto.Migration

  def change do
    alter table("attempts") do
      remove :updated_at, :naive_datetime_usec
    end
  end
end
