defmodule Lightning.Repo.Migrations.AddCredentialBodyToOauthTokens do
  use Ecto.Migration

  def change do
    alter table(:oauth_tokens) do
      add :credential_body_id,
          references(:credential_bodies, type: :binary_id, on_delete: :delete_all)
    end

    create index(:oauth_tokens, [:credential_body_id])
  end
end
