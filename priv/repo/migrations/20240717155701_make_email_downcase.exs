defmodule Lightning.Repo.Migrations.MakeEmailDowncase do
  use Ecto.Migration

  def change do
    execute "UPDATE users SET email = LOWER(email)"
  end
end
