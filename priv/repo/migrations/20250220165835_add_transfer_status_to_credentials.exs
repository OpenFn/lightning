defmodule Lightning.Repo.Migrations.AddTransferStatusToCredentials do
  use Ecto.Migration

  def change do
    alter table(:credentials) do
      add :transfer_status, :string
    end
  end
end
