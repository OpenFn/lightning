defmodule Lightning.Repo.Migrations.WidenCredentialsSchema do
  use Ecto.Migration

  def change do
    alter table(:credentials) do
      modify :schema, :string, size: 100, from: {:string, size: 40}
    end
  end
end
