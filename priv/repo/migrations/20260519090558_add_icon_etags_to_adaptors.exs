defmodule Lightning.Repo.Migrations.AddIconEtagsToAdaptors do
  use Ecto.Migration

  def change do
    alter table(:adaptors) do
      add :icon_square_etag, :string
      add :icon_rectangle_etag, :string
    end
  end
end
