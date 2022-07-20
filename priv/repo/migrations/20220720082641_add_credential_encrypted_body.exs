defmodule Lightning.Repo.Migrations.AddCredentialEncryptedBody do
  use Ecto.Migration

  def up do
    alter table(:credentials) do
      remove :body
      add :body, :binary
    end
  end

  def down do
    alter table(:credentials) do
      remove :body
      add :body, :map, default: %{}
    end
  end
end
