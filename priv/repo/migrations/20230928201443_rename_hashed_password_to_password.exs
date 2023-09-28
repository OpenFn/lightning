defmodule Lightning.Repo.Migrations.RenameHashedPasswordToPassword do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE webhook_auth_methods RENAME COLUMN hashed_password TO password;"
  end

  def down do
    execute "ALTER TABLE webhook_auth_methods RENAME COLUMN password TO hashed_password;"
  end
end
