defmodule Lightning.Repo.Migrations.AddScopesDocUrlToOauthClient do
  use Ecto.Migration

  def change do
    alter table(:oauth_clients) do
      add :scopes_doc_url, :string, null: true
    end
  end
end
