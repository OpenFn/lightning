defmodule Lightning.Repo.Migrations.UpdateScopesColumnsToText do
  use Ecto.Migration

  def change do
    alter table(:oauth_clients) do
      modify :mandatory_scopes, :text, null: true
      modify :optional_scopes, :text, null: true
    end
  end
end
