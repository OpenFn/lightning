defmodule Lightning.Repo.Migrations.AddErasedAtToDataclips do
  use Ecto.Migration

  def change do
    alter table("dataclips") do
      add :erased_at, :utc_datetime
    end
  end
end
